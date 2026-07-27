import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/models/vendor.dart';
import '../../core/state/auth_state.dart';
import 'order_history_screen.dart';
import 'vendor_menu_screen.dart';

class VendorListScreen extends StatefulWidget {
  const VendorListScreen({super.key});

  @override
  State<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends State<VendorListScreen> {
  late Future<List<Vendor>> _vendorsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _vendorsFuture = context.read<ApiClient>().listVendors();
  }

  Future<void> _refresh() async {
    setState(_load);
    await _vendorsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ร้านค้าในตลาดนัด'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'ประวัติการสั่ง',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Vendor>>(
          future: _vendorsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(onRetry: _refresh);
            }
            final vendors = snapshot.data!;
            if (vendors.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('ยังไม่มีร้านค้าเปิดขาย')),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: vendors.length,
              itemBuilder: (context, index) {
                final vendor = vendors[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(vendor.name.substring(0, 1))),
                  title: Text(vendor.name),
                  subtitle: Text([
                    if (vendor.stallNumber != null) 'ล็อค ${vendor.stallNumber}',
                    if (vendor.marketZone != null) vendor.marketZone!,
                    if (!vendor.isOpen) 'ปิดรับออเดอร์ชั่วคราว',
                  ].where((s) => s.isNotEmpty).join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => VendorMenuScreen(vendorId: vendor.id)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('โหลดข้อมูลไม่สำเร็จ'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    );
  }
}
