/// Formats a price stored as integer cents (satang) into a Thai Baht string,
/// e.g. 4000 -> "40.00 บาท".
String formatBaht(int cents) {
  final baht = cents / 100;
  return '${baht.toStringAsFixed(2)} บาท';
}
