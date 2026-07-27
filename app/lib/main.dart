import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/state/auth_state.dart';
import 'core/state/cart_state.dart';
import 'features/auth/login_screen.dart';
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
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider(create: (_) => AuthState(apiClient)),
        ChangeNotifierProvider(create: (_) => CartState()),
      ],
      child: MaterialApp(
        title: 'FaryHost',
        theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
        home: const AuthGate(),
      ),
    );
  }
}

/// Routes to the login flow, the customer home, or the vendor home based on
/// the signed-in user's role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }
    if (auth.user!.isVendor) {
      return const VendorDashboardScreen();
    }
    return const VendorListScreen();
  }
}
