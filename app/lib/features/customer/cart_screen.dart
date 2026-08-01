import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/format.dart';
import '../../core/state/cart_state.dart';
import 'order_status_screen.dart';

/// หน้าตะกร้า/เช็คเอาต์ — ยืนยันสั่งอาหารแล้วยิง POST /api/orders
/// backend จะสร้างรายการเก็บเงินกับ Omise (PromptPay QR) ให้ทันที ออเดอร์จะ
/// อยู่ในสถานะ "รอชำระเงิน" จนกว่าจะสแกนจ่ายสำเร็จ (ดู OrderStatusScreen ต่อ)
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _noteController = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _placeOrder() async {
    final cart = context.read<CartState>();
    if (cart.vendorId == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final order = await context.read<ApiClient>().createOrder(
            vendorId: cart.vendorId!,
            items: cart.toOrderItems(),
            note: _noteController.text.trim(),
          );
      cart.clear();
      if (!mounted) return;
      // แทนที่หน้าตะกร้าด้วยหน้าสถานะออเดอร์ (ไม่ push ซ้อน กันกดย้อนกลับมาสั่งซ้ำ)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderStatusScreen(orderId: order.id)),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'สั่งอาหารไม่สำเร็จ ลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartState>();

    return Scaffold(
      appBar: AppBar(title: const Text('ตะกร้าของฉัน')),
      body: cart.isEmpty
          ? const Center(child: Text('ตะกร้าว่าง'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final line in cart.lines)
                  ListTile(
                    title: Text(line.menuItem.name),
                    subtitle: Text(formatBaht(line.menuItem.priceCents)),
                    // ปุ่ม +/- ปรับจำนวน กดลบจนเหลือ 0 จะเอาออกจากตะกร้าเอง (ดู CartState.setQuantity)
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => context
                              .read<CartState>()
                              .setQuantity(line.menuItem.id, line.quantity - 1),
                        ),
                        Text('${line.quantity}'),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => context
                              .read<CartState>()
                              .setQuantity(line.menuItem.id, line.quantity + 1),
                        ),
                      ],
                    ),
                  ),
                const Divider(),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'หมายเหตุถึงร้านค้า (ไม่บังคับ)'),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ยอดรวม', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formatBaht(cart.totalCents), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _placeOrder,
                  child: _submitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ยืนยันและชำระเงิน'),
                ),
              ],
            ),
    );
  }
}
