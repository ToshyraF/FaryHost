import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'models/menu_item.dart';
import 'models/order.dart';
import 'models/user.dart';
import 'models/vendor.dart';

/// คุยกับ Go backend ใน backend/ ที่เดียว ทุกหน้าจอต้องเรียกผ่านคลาสนี้เท่านั้น
/// (ห้ามเรียก http package ตรงๆ จากหน้าจอ) เพื่อให้จุดคุยกับ API รวมอยู่ที่เดียว
///
/// ค่า default คือ backend รันที่ localhost:8080 — บน Android emulator
/// คำว่า localhost หมายถึงตัว emulator เอง ไม่ใช่เครื่องจริงที่รัน emulator
/// ให้ส่ง baseUrl: 'http://10.0.2.2:8080/api' แทนตอน new ApiClient()
class ApiClient {
  final String baseUrl;
  final http.Client _client;
  String? token; // JWT ที่ได้จาก login/register เก็บไว้แนบไปกับทุก request ที่ต้อง auth

  /// [client] ใส่ให้ override ได้สำหรับเทส (เช่น package:http/testing.dart's
  /// MockClient) ปกติไม่ต้องส่งค่านี้มา จะใช้ http.Client() จริงให้อัตโนมัติ
  ApiClient({this.baseUrl = 'http://localhost:8080/api', http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  /// แปลง response จาก backend เป็น JSON ถ้า status ไม่ใช่ 2xx จะโยน
  /// ApiException พร้อมข้อความ error ที่ backend ส่งมาให้
  Future<dynamic> _decode(http.Response res) async {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    final message =
        (body is Map && body['error'] is String) ? body['error'] as String : 'Request failed (${res.statusCode})';
    throw ApiException(res.statusCode, message);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _client.post(Uri.parse('$baseUrl$path'), headers: _headers(), body: jsonEncode(body));
    return await _decode(res) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final res = await _client.patch(Uri.parse('$baseUrl$path'), headers: _headers(), body: jsonEncode(body));
    return await _decode(res) as Map<String, dynamic>;
  }

  Future<dynamic> _get(String path) async {
    final res = await _client.get(Uri.parse('$baseUrl$path'), headers: _headers(json: false));
    return await _decode(res);
  }

  Future<void> _delete(String path) async {
    final res = await _client.delete(Uri.parse('$baseUrl$path'), headers: _headers(json: false));
    await _decode(res);
  }

  // --- Auth ---

  Future<AuthResult> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
  }) async {
    final json = await _post('/auth/register', {
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
      if (phone != null) 'phone': phone,
    });
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final json = await _post('/auth/login', {'email': email, 'password': password});
    return AuthResult.fromJson(json);
  }

  // --- ร้านค้า (public: ดูได้โดยไม่ต้อง login) ---

  Future<List<Vendor>> listVendors() async {
    final json = await _get('/vendors') as List<dynamic>;
    return json.map((e) => Vendor.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<VendorDetail> getVendorDetail(String id) async {
    final json = await _get('/vendors/$id') as Map<String, dynamic>;
    return VendorDetail.fromJson(json);
  }

  // --- ร้านค้าของตัวเอง (ต้อง login เป็น vendor) ---

  Future<Vendor> createVendor({
    required String name,
    String? description,
    String? stallNumber,
    String? marketZone,
  }) async {
    final json = await _post('/vendors/me', {
      'name': name,
      if (description != null) 'description': description,
      if (stallNumber != null) 'stall_number': stallNumber,
      if (marketZone != null) 'market_zone': marketZone,
    });
    return Vendor.fromJson(json);
  }

  /// คืน null ถ้า vendor user คนนี้ยังไม่เคยตั้งค่าร้านค้าไว้ (แทนที่จะโยน error)
  /// เพื่อให้ VendorDashboardScreen เอาไปเช็คแล้วโชว์ฟอร์มตั้งค่าร้านแทนได้ง่ายๆ
  Future<Vendor?> getMyVendor() async {
    try {
      final json = await _get('/vendors/me') as Map<String, dynamic>;
      return Vendor.fromJson(json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Vendor> updateMyVendor({
    required String name,
    String? description,
    String? stallNumber,
    String? marketZone,
    bool? isOpen,
  }) async {
    final json = await _patch('/vendors/me', {
      'name': name,
      'description': description ?? '',
      'stall_number': stallNumber ?? '',
      'market_zone': marketZone ?? '',
      if (isOpen != null) 'is_open': isOpen,
    });
    return Vendor.fromJson(json);
  }

  // --- เมนูของร้านตัวเอง ---

  Future<List<MenuItem>> listMyMenuItems() async {
    final json = await _get('/vendors/me/menu-items') as List<dynamic>;
    return json.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MenuItem> createMenuItem({
    required String name,
    required int priceCents,
    String? description,
  }) async {
    final json = await _post('/vendors/me/menu-items', {
      'name': name,
      'price_cents': priceCents,
      if (description != null) 'description': description,
    });
    return MenuItem.fromJson(json);
  }

  Future<MenuItem> updateMenuItem(
    String id, {
    required String name,
    required int priceCents,
    String? description,
    bool? isAvailable,
  }) async {
    final json = await _patch('/vendors/me/menu-items/$id', {
      'name': name,
      'price_cents': priceCents,
      'description': description ?? '',
      if (isAvailable != null) 'is_available': isAvailable,
    });
    return MenuItem.fromJson(json);
  }

  Future<void> deleteMenuItem(String id) => _delete('/vendors/me/menu-items/$id');

  // --- ออเดอร์ ---

  Future<Order> createOrder({
    required String vendorId,
    required List<Map<String, dynamic>> items,
    String? note,
  }) async {
    final json = await _post('/orders', {
      'vendor_id': vendorId,
      'items': items,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return Order.fromJson(json);
  }

  Future<List<Order>> listMyOrders() async {
    final json = await _get('/orders/me') as List<dynamic>;
    return json.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> getOrder(String id) async {
    final json = await _get('/orders/$id') as Map<String, dynamic>;
    return Order.fromJson(json);
  }

  Future<List<Order>> listVendorOrders() async {
    final json = await _get('/vendors/me/orders') as List<dynamic>;
    return json.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Order> updateOrderStatus(String id, String status) async {
    final json = await _patch('/orders/$id/status', {'status': status});
    return Order.fromJson(json);
  }
}

/// ผลลัพธ์จากการ login/register: token ไว้เรียก API อื่นต่อ + ข้อมูลผู้ใช้
class AuthResult {
  final String token;
  final AppUser user;

  AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: json['token'] as String,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
