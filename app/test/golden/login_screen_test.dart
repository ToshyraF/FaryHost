import 'package:flutter_test/flutter_test.dart';

import 'package:faryhost_app/features/auth/login_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('LoginScreen แสดงผลถูกต้อง', (tester) async {
    await pumpGolden(tester, const LoginScreen());

    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login_screen.png'),
    );
  });
}
