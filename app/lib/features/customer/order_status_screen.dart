import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models/order.dart';

/// หน้าจอติดตามสถานะออเดอร์ 1 รายการ — ตอนสถานะเป็น "รอชำระเงิน" จะโชว์ QR
/// PromptPay ให้สแกนจ่าย พอจ่ายสำเร็จ (ระบบเปลี่ยนสถานะให้อัตโนมัติ) จะเปลี่ยน
/// มาโชว์รหัสรับอาหารตัวใหญ่ๆ ให้เอาไปยื่นให้ร้านค้าตอนไปรับของแทน
class OrderStatusScreen extends StatefulWidget {
  final String orderId;

  const OrderStatusScreen({super.key, required this.orderId});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  Order? _order;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // ทำ "live status" แบบประหยัดๆ โดยไม่ต้องใช้ websocket: ดึงข้อมูลใหม่ทุก 5
    // วินาทีระหว่างที่หน้าจอนี้เปิดอยู่ แล้วหยุดเองเมื่อออเดอร์ถึงสถานะจบแล้ว
    // การ poll นี้ยังทำหน้าที่เช็คสถานะการจ่ายเงินซ้ำไปในตัวด้วย (ฝั่ง backend
    // จะยืนยันกับ Omise ให้ทุกครั้งที่ GetOrder ถูกเรียกตอนยังรอจ่ายเงินอยู่)
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final order = await context.read<ApiClient>().getOrder(widget.orderId);
      if (!mounted) return;
      setState(() => _order = order);
      if (order.status == OrderStatus.completed || order.status == OrderStatus.cancelled) {
        _poll?.cancel();
      }
    } catch (_) {
      // เน็ตหลุดชั่วคราวก็ไม่เป็นไร โชว์ข้อมูลล่าสุดที่มีไปก่อน รอบถัดไปจะลองใหม่เอง
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('สถานะออเดอร์')),
      body: order == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  order.status == OrderStatus.awaitingPayment
                      ? _PaymentQRSection(order: order)
                      : _PickupCodeSection(order: order),
                  const SizedBox(height: 24),
                  const Divider(),
                  for (final item in order.items)
                    ListTile(
                      title: Text(item.nameSnapshot),
                      subtitle: Text('x${item.quantity}'),
                      trailing: Text(formatBaht(item.subtotalCents)),
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ยอดรวม', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(formatBaht(order.totalCents), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (order.note != null && order.note!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('หมายเหตุ: ${order.note}'),
                  ],
                ],
              ),
            ),
    );
  }
}

/// ส่วนหัวตอนออเดอร์ยังไม่จ่ายเงิน: QR PromptPay ให้สแกน — ไม่มีทางเลือกจ่าย
/// เงินสดหน้าร้านแล้ว ต้องจ่ายผ่าน QR นี้ก่อน ร้านค้าถึงจะเห็นออเดอร์
class _PaymentQRSection extends StatelessWidget {
  final Order order;

  const _PaymentQRSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('สแกน QR เพื่อชำระเงินผ่านแอปธนาคาร (PromptPay)', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Container(
          width: 240,
          height: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
          child: order.paymentQRCodeUri != null
              ? Image.network(
                  order.paymentQRCodeUri!,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Icon(Icons.qr_code_2, size: 96)),
                )
              : const Center(child: Icon(Icons.qr_code_2, size: 96)),
        ),
        const SizedBox(height: 16),
        Text(
          formatBaht(order.totalCents),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Chip(label: Text(OrderStatus.label(order.status))),
      ],
    );
  }
}

/// ส่วนหัวตอนออเดอร์จ่ายเงินแล้ว (หรือกำลังดำเนินการอยู่): รหัสรับอาหาร
class _PickupCodeSection extends StatelessWidget {
  final Order order;

  const _PickupCodeSection({required this.order});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('รหัสรับอาหาร'),
        Text(
          order.code,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 4),
        ),
        const SizedBox(height: 8),
        Chip(label: Text(OrderStatus.label(order.status))),
      ],
    );
  }
}
