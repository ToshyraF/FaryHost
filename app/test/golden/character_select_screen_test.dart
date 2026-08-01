import 'package:flutter_test/flutter_test.dart';

import 'package:faryhost_app/features/customer/character_select_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('CharacterSelectScreen แสดงตัวละครทั้ง 10 แบบ', (tester) async {
    await pumpGolden(tester, const CharacterSelectScreen());

    await expectLater(
      find.byType(CharacterSelectScreen),
      matchesGoldenFile('goldens/character_select_screen.png'),
    );
  });

  testWidgets('CharacterSelectScreen แบบ mandatory ไม่มีปุ่มย้อนกลับ', (tester) async {
    await pumpGolden(tester, const CharacterSelectScreen(mandatory: true));

    await expectLater(
      find.byType(CharacterSelectScreen),
      matchesGoldenFile('goldens/character_select_screen_mandatory.png'),
    );
  });
}
