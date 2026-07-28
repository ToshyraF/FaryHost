import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/user.dart';

/// เก็บสถานะการ login ไว้ทั้งแอป (ผ่าน provider) และจำ session ไว้ใน
/// shared_preferences เพื่อให้เปิดแอปใหม่แล้วไม่ต้อง login ซ้ำ
class AuthState extends ChangeNotifier {
  final ApiClient apiClient;

  AppUser? _user;
  bool _loading = true; // true ระหว่างที่กำลังโหลด session เก่าจาก storage ตอนเปิดแอป

  AuthState(this.apiClient) {
    _restore();
  }

  AppUser? get user => _user;
  bool get isLoading => _loading;
  bool get isLoggedIn => _user != null;

  /// ตอนเปิดแอป เช็คว่ามี token/user ที่เคย login ไว้ค้างอยู่ใน storage ไหม
  /// ถ้ามีก็เอามาใช้ต่อเลยโดยไม่ต้อง login ใหม่
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userJson = prefs.getString('auth_user');
    if (token != null && userJson != null) {
      try {
        _user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        apiClient.token = token;
      } catch (_) {
        // ข้อมูลที่ cache ไว้เสียหายหรือรูปแบบเปลี่ยนไป ให้ logout แทนที่จะ crash
        await logout();
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    final result = await apiClient.login(email: email, password: password);
    await _onAuthenticated(result);
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
  }) async {
    final result = await apiClient.register(
      email: email,
      password: password,
      fullName: fullName,
      role: role,
      phone: phone,
    );
    await _onAuthenticated(result);
  }

  /// เก็บ token + user ไว้ทั้งใน memory (ให้ ApiClient ใช้เรียก API ต่อ) และ
  /// ใน shared_preferences (ให้จำ session ข้ามการเปิดแอปใหม่ได้)
  Future<void> _onAuthenticated(AuthResult result) async {
    apiClient.token = result.token;
    _user = result.user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', result.token);
    await prefs.setString('auth_user', jsonEncode(result.user.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    apiClient.token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');
    notifyListeners();
  }
}
