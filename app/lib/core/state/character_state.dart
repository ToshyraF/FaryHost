import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character_option.dart';

/// เก็บว่าลูกค้าเลือกตัวละคร (avatar) แบบไหนอยู่ ทั้งใน memory (ผ่าน provider)
/// และใน shared_preferences (จำข้ามการเปิดแอปใหม่ได้ เหมือน AuthState)
class CharacterState extends ChangeNotifier {
  String _selectedId = kDefaultCharacterId;

  CharacterState() {
    _restore();
  }

  CharacterOption get selected => characterById(_selectedId);

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_character_id');
    if (saved != null) {
      _selectedId = saved;
      notifyListeners();
    }
  }

  Future<void> select(String characterId) async {
    _selectedId = characterId;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_character_id', characterId);
  }
}
