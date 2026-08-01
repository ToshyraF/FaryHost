import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/vendor.dart';
import '../../core/state/cart_state.dart';
import 'cart_screen.dart';

/// หน้าเมนูของร้านค้า 1 ร้าน — ลูกค้ากดเพิ่มเมนูลงตะกร้าจากหน้านี้
class VendorMenuScreen extends StatefulWidget {
  final String vendorId;

  const VendorMenuScreen({super.key, required this.vendorId});

  @override
  State<VendorMenuScreen> createState() => _VendorMenuScreenState();
}

class _VendorMenuScreenState extends State<VendorMenuScreen> {
  late Future<VendorDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<ApiClient>().getVendorDetail(widget.vendorId);
  }

  /// เพิ่มเมนูลงตะกร้า ถ้าตะกร้าเดิมเป็นของร้านอื่นอยู่ (CartState จะล้างให้เอง)
  /// จะแจ้งเตือนให้ลูกค้ารู้ว่าตะกร้าเก่าถูกล้างไปแล้ว
  void _addToCart(VendorDetail vendor, MenuItem item) {
    final cart = context.read<CartState>();
    final switchedVendor = cart.belongsToOtherVendor(vendor.id);
    cart.addItem(vendor.id, item);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switchedVendor ? 'เริ่มตะกร้าใหม่สำหรับ ${vendor.name}' : 'เพิ่ม ${item.name} ในตะกร้าแล้ว'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<VendorDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('โหลดข้อมูลร้านไม่สำเร็จ'));
          }
          final vendor = snapshot.data!;
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                title: Text(vendor.name),
                pinned: true,
              ),
              if (!vendor.isOpen)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Card(
                      color: Color(0xFFFFF3E0),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('ร้านนี้ปิดรับออเดอร์ชั่วคราว'),
                      ),
                    ),
                  ),
                ),
              if (vendor.description != null && vendor.description!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(vendor.description!),
                  ),
                ),
              SliverList.builder(
                itemCount: vendor.menuItems.length,
                itemBuilder: (context, index) {
                  final item = vendor.menuItems[index];
                  return ListTile(
                    title: Text(item.name),
                    subtitle: Text(
                      [
                        formatBaht(item.priceCents),
                        if (!item.isAvailable) 'หมดชั่วคราว',
                      ].join(' · '),
                    ),
                    // กดเพิ่มลงตะกร้าได้เฉพาะตอนร้านเปิดและเมนูยังมีขายอยู่เท่านั้น
                    trailing: (vendor.isOpen && item.isAvailable)
                        ? IconButton(
                            icon: const Icon(Icons.add_circle),
                            onPressed: () => _addToCart(vendor, item),
                          )
                        : null,
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          );
        },
      ),
      // แถบล่างโชว์ตะกร้าแบบลอย จะขึ้นก็ต่อเมื่อตะกร้ามีของและเป็นของร้านนี้เท่านั้น
      bottomNavigationBar: Consumer<CartState>(
        builder: (context, cart, _) {
          if (cart.isEmpty || cart.vendorId != widget.vendorId) return const SizedBox.shrink();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
                child: Text('ดูตะกร้า (${cart.itemCount}) · ${formatBaht(cart.totalCents)}'),
              ),
            ),
          );
        },
      ),
    );
  }
}
