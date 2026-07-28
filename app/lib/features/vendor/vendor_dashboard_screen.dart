import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/models/vendor.dart';
import '../../core/state/auth_state.dart';
import 'menu_management_tab.dart';
import 'vendor_orders_tab.dart';

/// หน้าหลักของฝั่งร้านค้า — เช็คก่อนว่าเคยตั้งค่าร้านไว้หรือยัง
/// (getMyVendor() == null) ถ้ายัง จะโชว์ฟอร์มตั้งค่าร้านแทน dashboard
class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  late Future<Vendor?> _vendorFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _vendorFuture = context.read<ApiClient>().getMyVendor();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Vendor?>(
      future: _vendorFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) {
          return _CreateStallScreen(onCreated: () => setState(_load));
        }
        return _VendorHome(vendor: snapshot.data!, onVendorUpdated: () => setState(_load));
      },
    );
  }
}

/// dashboard ของร้านค้าที่ตั้งค่าเสร็จแล้ว มี 2 แท็บ: คำสั่งซื้อ กับ เมนู
/// (เป็น widget ธรรมดาฝังใน TabBarView ไม่ใช่คนละหน้าจอแยก)
class _VendorHome extends StatelessWidget {
  final Vendor vendor;
  final VoidCallback onVendorUpdated;

  const _VendorHome({required this.vendor, required this.onVendorUpdated});

  /// เปิด/ปิดรับออเดอร์ — ต้องส่งข้อมูลเดิมของร้าน (ชื่อ/รายละเอียด/ล็อค/โซน)
  /// กลับไปด้วยเสมอ เพราะ backend เขียนทับทุก field ที่ส่งมาใน PATCH ตัวนี้
  Future<void> _toggleOpen(BuildContext context, bool value) async {
    await context.read<ApiClient>().updateMyVendor(
          name: vendor.name,
          description: vendor.description,
          stallNumber: vendor.stallNumber,
          marketZone: vendor.marketZone,
          isOpen: value,
        );
    onVendorUpdated();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(vendor.name),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Text(vendor.isOpen ? 'เปิดรับออเดอร์' : 'ปิดรับออเดอร์'),
                  Switch(value: vendor.isOpen, onChanged: (v) => _toggleOpen(context, v)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'ออกจากระบบ',
              onPressed: () => context.read<AuthState>().logout(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'คำสั่งซื้อ'),
              Tab(text: 'เมนู'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            VendorOrdersTab(vendorId: vendor.id),
            const MenuManagementTab(),
          ],
        ),
      ),
    );
  }
}

/// ฟอร์มตั้งค่าร้านค้าครั้งแรก (แสดงเฉพาะตอนที่ vendor user ยังไม่เคยสร้างร้านเลย)
class _CreateStallScreen extends StatefulWidget {
  final VoidCallback onCreated;

  const _CreateStallScreen({required this.onCreated});

  @override
  State<_CreateStallScreen> createState() => _CreateStallScreenState();
}

class _CreateStallScreenState extends State<_CreateStallScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _stallNumberController = TextEditingController();
  final _marketZoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _stallNumberController.dispose();
    _marketZoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().createVendor(
            name: _nameController.text.trim(),
            description: _descriptionController.text.trim(),
            stallNumber: _stallNumberController.text.trim(),
            marketZone: _marketZoneController.text.trim(),
          );
      widget.onCreated();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'สร้างร้านค้าไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าร้านค้า'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ตั้งค่าร้านค้าของคุณก่อนเริ่มขาย', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'ชื่อร้าน'),
                    validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกชื่อร้าน' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _stallNumberController,
                    decoration: const InputDecoration(labelText: 'เลขล็อค (ไม่บังคับ)'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _marketZoneController,
                    decoration: const InputDecoration(labelText: 'โซน/ตลาด (ไม่บังคับ)'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(labelText: 'รายละเอียดร้าน (ไม่บังคับ)'),
                    maxLines: 3,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('เริ่มขาย'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
