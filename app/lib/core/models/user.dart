/// ผู้ใช้งาน 1 คน ใช้ตารางเดียวกันทั้งลูกค้าและร้านค้า แยกกันด้วย [role]
class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String role; // "customer" หรือ "vendor"
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
    this.phone,
  });

  bool get isVendor => role == 'vendor';
  bool get isCustomer => role == 'customer';

  /// แปลง JSON ที่ backend ส่งมาให้เป็น AppUser (เขียนเองแทน code generation
  /// เพราะแซนด์บ็อกซ์นี้ไม่มี Flutter/Dart SDK ให้รัน build_runner)
  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// แปลงกลับเป็น JSON เพื่อเก็บ cache ไว้ใน shared_preferences (ดู AuthState)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
