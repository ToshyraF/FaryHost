import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faryhost_app/core/api_client.dart';
import 'package:faryhost_app/core/state/auth_state.dart';
import 'package:faryhost_app/core/state/cart_state.dart';
import 'package:faryhost_app/core/state/character_state.dart';
import 'package:faryhost_app/core/theme.dart';

/// ห่อ widget ที่จะเทสด้วย MultiProvider + MaterialApp แบบเดียวกับที่ main.dart
/// ทำจริง เพื่อให้ widget ที่เรียก context.read<ApiClient/AuthState/CartState>()
/// ทำงานได้เหมือนตอนรันแอปจริง
///
/// [apiClient] ปกติควรส่ง ApiClient ที่ผูกกับ MockClient (package:http/testing.dart)
/// เพื่อไม่ให้เทสยิง network จริง — ดูตัวอย่างใน vendor_list_screen_test.dart
///
/// [settle] ตั้งเป็น false สำหรับหน้าจอที่มี game loop ทำงานตลอดเวลา (เช่น
/// Flame's GameWidget ใน market_map_game_screen_test.dart) เพราะ
/// pumpAndSettle() จะรอ "จนกว่าจะไม่มี frame ใหม่ถูก schedule" ซึ่งไม่มีวัน
/// เกิดขึ้นกับ game loop ที่ render ต่อเนื่องไปเรื่อยๆ — เทสจะค้าง/timeout
/// ถ้าเรียก pumpAndSettle() ใส่หน้าจอแบบนี้ ผู้เรียกต้อง tester.pump() เอง
/// เป็นจำนวนรอบที่กำหนดแทน
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  ApiClient? apiClient,
  CartState? cartState,
  Size surfaceSize = const Size(400, 800),
  bool settle = true,
}) async {
  // AuthState._restore() อ่าน SharedPreferences ตอนสร้าง ต้อง mock ค่าเริ่มต้น
  // ไว้ก่อน ไม่งั้นจะ throw เพราะไม่มี plugin จริงใน widget test
  SharedPreferences.setMockInitialValues({});

  final client = apiClient ?? ApiClient();

  tester.view.physicalSize = surfaceSize * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: client),
        ChangeNotifierProvider(create: (_) => AuthState(client)),
        ChangeNotifierProvider(create: (_) => cartState ?? CartState()),
        ChangeNotifierProvider(create: (_) => CharacterState()),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}
