/// แปลงราคาที่เก็บเป็นจำนวนเต็มหน่วยสตางค์ ให้เป็นข้อความสกุลเงินบาท
/// เช่น 4000 -> "40.00 บาท"
String formatBaht(int cents) {
  final baht = cents / 100;
  return '${baht.toStringAsFixed(2)} บาท';
}
