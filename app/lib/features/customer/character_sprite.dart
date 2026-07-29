import 'package:flutter/material.dart';

const _frameSize = 32.0;
const _sheetGrid = 4; // ตาราง 4x4 เฟรม (แถว/คอลัมน์) ในทุก sprite sheet

/// แสดง 1 เฟรมจาก sprite sheet ตาราง 4x4 (32x32 ต่อเฟรม) ขยายให้เป็นสี่เหลี่ยม
/// ขนาด [displaySize] คมชัดแบบพิกเซลอาร์ต (ไม่ blur ตอนขยาย) — โหลดทั้งภาพผ่าน
/// Image.asset ปกติแล้วครอปด้วย OverflowBox + Transform.translate (ค่าตำแหน่ง
/// ระบุตรงๆ ทั้งหมด ไม่พึ่งพา alignment แบบสัดส่วนที่เคยทำให้ระบุตำแหน่งผิดมาก่อน)
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
        child: OverflowBox(
          maxWidth: sheetSize,
          maxHeight: sheetSize,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-col * displaySize, -row * displaySize),
            child: Image.asset(
              assetPath,
              width: sheetSize,
              height: sheetSize,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
      ),
    );
  }
}
