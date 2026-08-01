import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models/menu_item.dart';
import '../../core/models/vendor.dart';
import '../../core/state/cart_state.dart';
import 'cart_screen.dart';

/// เมนูร้านค้าแบบ popup — ใช้ตอนเดินเข้าใกล้/แตะร้านค้าในหน้าเดินเล่นในตลาด
/// (`MarketMapGameScreen`) แสดงผ่าน `showModalBottomSheet` ทับแผนที่อยู่แทน
/// การ push ไปหน้าใหม่ทั้งหน้าแบบ `VendorMenuScreen` (ซึ่งยังใช้จากหน้ารายชื่อ
/// ร้านค้าแบบ list ตามเดิม) เพื่อให้ลูกค้าดูเมนู/เพิ่มตะกร้าได้โดยไม่หลุดออก
/// จากแผนที่ — ปิด popup ก็กลับมาเดินต่อได้ทันที ไม่ใช่การ "landing" ไปหน้าอื่น
class VendorMenuSheet extends StatefulWidget {
  final String vendorId;

  const VendorMenuSheet({super.key, required this.vendorId});

  @override
  State<VendorMenuSheet> createState() => _VendorMenuSheetState();
}

class _VendorMenuSheetState extends State<VendorMenuSheet> {
  late Future<VendorDetail> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<ApiClient>().getVendorDetail(widget.vendorId);
  }

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
    // สูงประมาณ 70% ของจอ พอสำหรับรายการเมนูจริง แต่ยังเห็นแผนที่ (dim ไว้)
    // อยู่ด้านหลัง ต่างจากการ push หน้าใหม่ทั้งหน้าซึ่งจะบังแผนที่มิดไปเลย
    final sheetHeight = MediaQuery.of(context).size.height * 0.7;
    return SizedBox(
      height: sheetHeight,
      child: SafeArea(
        top: false,
        child: FutureBuilder<VendorDetail>(
          future: _detailFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('โหลดข้อมูลร้านไม่สำเร็จ'));
            }
            final vendor = snapshot.data!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(vendor.name, style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'ปิด',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                if (!vendor.isOpen)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Card(
                      color: Color(0xFFFFF3E0),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('ร้านนี้ปิดรับออเดอร์ชั่วคราว'),
                      ),
                    ),
                  ),
                if (vendor.description != null && vendor.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(vendor.description!),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
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
                        trailing: (vendor.isOpen && item.isAvailable)
                            ? IconButton(
                                icon: const Icon(Icons.add_circle),
                                onPressed: () => _addToCart(vendor, item),
                              )
                            : null,
                      );
                    },
                  ),
                ),
                Consumer<CartState>(
                  builder: (context, cart, _) {
                    if (cart.isEmpty || cart.vendorId != widget.vendorId) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CartScreen()),
                        ),
                        child: Text('ดูตะกร้า (${cart.itemCount}) · ${formatBaht(cart.totalCents)}'),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
