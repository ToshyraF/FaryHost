import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/user.dart';

class AuthState extends ChangeNotifier {
  final ApiClient apiClient;

  AppUser? _user;
  bool _loading = true;

  AuthState(this.apiClient) {
    _restore();
  }

  AppUser? get user => _user;
  bool get isLoading => _loading;
  bool get isLoggedIn => _user != null;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userJson = prefs.getString('auth_user');
    if (token != null && userJson != null) {
      try {
        _user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
        apiClient.token = token;
      } catch (_) {
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
