import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/character_option.dart';
import '../../core/state/auth_state.dart';
import '../../core/state/character_state.dart';
import 'character_sprite.dart';

/// หน้าเลือกตัวละคร (avatar) สำหรับเดินในตลาด — แสดงท่ายืน (แถวหันลง เฟรม 0)
/// ของทุกตัวเป็นตาราง แตะตัวไหนก็เลือกตัวนั้นทันที
///
/// ใช้ 2 บริบท: (1) ปกติ เปิดจากปุ่มในแอปบาร์ของ MarketMapGameScreen แบบ
/// push แล้ว pop กลับหลังเลือก (2) [mandatory] — AuthGate เด้งมาที่นี่ตรงๆ
/// (ไม่ได้ push จึงไม่มีอะไรให้ pop กลับ) ทันทีที่ลูกค้าสมัครสมาชิกใหม่เสร็จ
/// เลือกแล้วเรียก AuthState.clearJustRegistered() แทน ให้ AuthGate สลับไปหน้า
/// เดินเล่นในตลาดเองแทนการ pop
class CharacterSelectScreen extends StatelessWidget {
  final bool mandatory;

  const CharacterSelectScreen({super.key, this.mandatory = false});

  @override
  Widget build(BuildContext context) {
    final characterState = context.watch<CharacterState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(mandatory ? 'เลือกตัวละครของคุณ' : 'เลือกตัวละคร'),
        automaticallyImplyLeading: !mandatory,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        itemCount: kCharacterOptions.length,
        itemBuilder: (context, index) {
          final option = kCharacterOptions[index];
          final isSelected = option.id == characterState.selected.id;
          return GestureDetector(
            onTap: () {
              characterState.select(option.id);
              if (mandatory) {
                context.read<AuthState>().clearJustRegistered();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.brown.shade100,
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: Center(
                child: CharacterSprite(
                  assetPath: option.assetPath,
                  row: 0,
                  col: 0,
                  displaySize: 64,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
