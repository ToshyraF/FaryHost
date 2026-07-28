import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/state/auth_state.dart';
import 'core/state/cart_state.dart';
import 'core/theme.dart';
import 'features/auth/welcome_screen.dart';
import 'features/customer/vendor_list_screen.dart';
import 'features/vendor/vendor_dashboard_screen.dart';

void main() {
  final apiClient = ApiClient();
  runApp(FaryHostApp(apiClient: apiClient));
}

class FaryHostApp extends StatelessWidget {
  final ApiClient apiClient;

  const FaryHostApp({super.key, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    // MultiProvider ทำให้ทุกหน้าจอในแอปเข้าถึง ApiClient, AuthState, CartState
    // ได้ผ่าน context.read<T>()/context.watch<T>() โดยไม่ต้องส่งผ่าน constructor
    // ทีละชั้น (dependency injection แบบง่ายๆ)
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider(create: (_) => AuthState(apiClient)),
        ChangeNotifierProvider(create: (_) => CartState()),
      ],
      child: MaterialApp(
        title: 'FaryHost',
        theme: buildAppTheme(),
        home: const AuthGate(),
      ),
    );
  }
}

/// ตัวตัดสินใจ routing แบบ role-based ตัวเดียวของแอป: ยังไม่ login ไปหน้า
/// ต้อนรับ (เลือกเข้าสู่ระบบ/สมัครสมาชิกจากตรงนั้น), login แล้วเป็น vendor
/// ไปหน้า dashboard ร้านค้า, login แล้วเป็น customer ไปหน้ารายชื่อร้านค้า
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isLoggedIn) {
      return const WelcomeScreen();
    }
    if (auth.user!.isVendor) {
      return const VendorDashboardScreen();
    }
    return const VendorListScreen();
  }
}
