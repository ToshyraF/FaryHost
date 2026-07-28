import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faryhost_app/core/api_client.dart';
import 'package:faryhost_app/core/state/auth_state.dart';
import 'package:faryhost_app/core/state/cart_state.dart';

/// ห่อ widget ที่จะเทสด้วย MultiProvider + MaterialApp แบบเดียวกับที่ main.dart
/// ทำจริง เพื่อให้ widget ที่เรียก context.read<ApiClient/AuthState/CartState>()
/// ทำงานได้เหมือนตอนรันแอปจริง
///
/// [apiClient] ปกติควรส่ง ApiClient ที่ผูกกับ MockClient (package:http/testing.dart)
/// เพื่อไม่ให้เทสยิง network จริง — ดูตัวอย่างใน vendor_list_screen_test.dart
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  ApiClient? apiClient,
  CartState? cartState,
  Size surfaceSize = const Size(400, 800),
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
      ],
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
