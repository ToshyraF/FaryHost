import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:faryhost_app/features/auth/register_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('RegisterScreen แสดงผลถูกต้อง (เลือก "ลูกค้า" เป็นค่าเริ่มต้น)', (tester) async {
    await pumpGolden(tester, const RegisterScreen(), surfaceSize: const Size(400, 900));

    await expectLater(
      find.byType(RegisterScreen),
      matchesGoldenFile('goldens/register_screen.png'),
    );
  });
}
