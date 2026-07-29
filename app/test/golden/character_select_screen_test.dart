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
}
