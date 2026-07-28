/// error ที่โยนออกมาเมื่อ backend ตอบกลับด้วย status code ที่ไม่ใช่ 2xx
/// โดย [message] คือข้อความจาก field "error" ใน JSON response ของ backend
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
