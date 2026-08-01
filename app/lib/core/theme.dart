import 'package:flutter/material.dart';

/// ธีมเดียวที่ทั้งแอปจริง (main.dart) และ golden test harness
/// (test/test_helpers.dart) ต้องใช้ร่วมกัน แยกออกมาเป็นไฟล์เดียวกันตรงนี้
/// เพื่อไม่ให้สอง MaterialApp คนละที่ตั้งค่า fontFamily ไม่ตรงกันโดยไม่ได้ตั้งใจ
/// (ถ้าไม่ตรงกัน ภาพ golden ที่ render จะไม่ใช้ font 'Loma' ที่โหลดไว้)
ThemeData buildAppTheme() {
  return ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true, fontFamily: 'Loma');
}
