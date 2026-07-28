import 'package:flutter_test/flutter_test.dart';

import 'package:faryhost_app/features/auth/welcome_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('WelcomeScreen แสดงผลถูกต้อง', (tester) async {
    await pumpGolden(tester, const WelcomeScreen());

    await expectLater(
      find.byType(WelcomeScreen),
      matchesGoldenFile('goldens/welcome_screen.png'),
    );
  });
}
