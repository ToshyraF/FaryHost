import 'package:flutter/material.dart';

const _sheetGrid = 4; // ตาราง 4x4 เฟรม (แถว/คอลัมน์) ในทุก sprite sheet

/// แสดง 1 เฟรมจาก sprite sheet ตาราง 4x4 (32x32 ต่อเฟรม) ขยายให้เป็นสี่เหลี่ยม
/// ขนาด [displaySize] คมชัดแบบพิกเซลอาร์ต (ไม่ blur ตอนขยาย) — โหลดทั้งภาพผ่าน
/// Image.asset ปกติแล้วครอปด้วย Stack + Positioned ที่ระบุ left/top/width/
/// height ตรงๆ ทั้งสี่ค่า (ไม่ใช่ OverflowBox + alignment ซึ่งเป็นกลไกเดียวกับ
/// Align แบบสัดส่วนที่เคยทำให้ตัวละครหายไปทั้งตัวมาก่อนหน้านี้ในโปรเจกต์นี้)
class CharacterSprite extends StatelessWidget {
  final String assetPath;
  final int row;
  final int col;
  final double displaySize;

  const CharacterSprite({
    super.key,
    required this.assetPath,
    required this.row,
    required this.col,
    required this.displaySize,
  });

  @override
  Widget build(BuildContext context) {
    final sheetSize = _sheetGrid * displaySize;
    return ClipRect(
      child: SizedBox(
        width: displaySize,
        height: displaySize,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -col * displaySize,
              top: -row * displaySize,
              width: sheetSize,
              height: sheetSize,
              child: Image.asset(
                assetPath,
                width: sheetSize,
                height: sheetSize,
                filterQuality: FilterQuality.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
