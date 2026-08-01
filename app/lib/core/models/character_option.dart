/// ตัวละคร (avatar) หนึ่งแบบที่ลูกค้าเลือกใช้เดินในตลาดได้ — sprite sheet แต่ละ
/// ไฟล์เป็นตาราง 4x4 เฟรมขนาด 32x32: แถว 0=หันลง(หน้า), 1=หันซ้าย, 2=หันขวา,
/// 3=หันขึ้น(หลัง), คอลัมน์ 0-3 คือ walk cycle ที่ต่อเนื่องกัน — ที่มา/สิทธิ์การ
/// ใช้งานอยู่ใน assets/sprites/CREDITS.txt
class CharacterOption {
  final String id;
  final String assetPath;

  const CharacterOption({required this.id, required this.assetPath});
}

const kCharacterOptions = <CharacterOption>[
  CharacterOption(id: 'character_01', assetPath: 'assets/sprites/character_01.png'),
  CharacterOption(id: 'character_02', assetPath: 'assets/sprites/character_02.png'),
  CharacterOption(id: 'character_03', assetPath: 'assets/sprites/character_03.png'),
  CharacterOption(id: 'character_04', assetPath: 'assets/sprites/character_04.png'),
  CharacterOption(id: 'character_05', assetPath: 'assets/sprites/character_05.png'),
  CharacterOption(id: 'character_06', assetPath: 'assets/sprites/character_06.png'),
  CharacterOption(id: 'character_07', assetPath: 'assets/sprites/character_07.png'),
  CharacterOption(id: 'character_08', assetPath: 'assets/sprites/character_08.png'),
  CharacterOption(id: 'character_09', assetPath: 'assets/sprites/character_09.png'),
  CharacterOption(id: 'character_10', assetPath: 'assets/sprites/character_10.png'),
];

const kDefaultCharacterId = 'character_01';

CharacterOption characterById(String id) {
  return kCharacterOptions.firstWhere(
    (c) => c.id == id,
    orElse: () => kCharacterOptions.first,
  );
}
