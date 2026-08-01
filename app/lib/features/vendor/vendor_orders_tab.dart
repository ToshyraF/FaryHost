import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models/order.dart';

/// แท็บคำสั่งซื้อของร้านค้า: โชว์ออเดอร์ที่เข้ามา พร้อมปุ่มเปลี่ยนสถานะ
/// (รับออเดอร์ / กำลังทำ / พร้อมรับ / เสร็จสิ้น / ยกเลิก) ตามกติกาใน
/// OrderStatus.nextStatuses
class VendorOrdersTab extends StatefulWidget {
  final String vendorId;

  const VendorOrdersTab({super.key, required this.vendorId});

  @override
  State<VendorOrdersTab> createState() => _VendorOrdersTabState();
}

class _VendorOrdersTabState extends State<VendorOrdersTab> {
  List<Order>? _orders;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // ดึงออเดอร์ใหม่ทุก 8 วินาที เพื่อให้ร้านค้าเห็นออเดอร์เข้าใหม่โดยไม่ต้อง
    // pull-to-refresh เองตลอดเวลา (ไม่ใช้ websocket เพื่อความง่าย)
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final orders = await context.read<ApiClient>().listVendorOrders();
      if (mounted) setState(() => _orders = orders);
    } catch (_) {
      // เน็ตหลุดชั่วคราวก็ไม่เป็นไร โชว์รายการล่าสุดที่มีไปก่อน รอบถัดไปจะลองใหม่เอง
    }
  }

  Future<void> _advance(Order order, String nextStatus) async {
    await context.read<ApiClient>().updateOrderStatus(order.id, nextStatus);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    if (orders == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // ออเดอร์ที่ยังต้องจัดการ (ยังไม่จบ) ควรอยู่บนสุด ส่วนที่จบแล้วไหลลงล่าง
    final active = orders.where((o) => o.status != OrderStatus.completed && o.status != OrderStatus.cancelled);
    final done = orders.where((o) => o.status == OrderStatus.completed || o.status == OrderStatus.cancelled);
    final sorted = [...active, ...done];

    if (sorted.isEmpty) {
      return const Center(child: Text('ยังไม่มีคำสั่งซื้อเข้ามา'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final order = sorted[index];
          // ตัวเลือกสถานะถัดไปที่กดได้ ดึงมาจากกติกาเดียวกับ backend
          // (models.NextStatuses ฝั่ง Go / OrderStatus.nextStatuses ฝั่งนี้)
          final nextOptions = OrderStatus.nextStatuses[order.status] ?? const <String>[];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('รหัส ${order.code}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      Chip(label: Text(OrderStatus.label(order.status))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final item in order.items) Text('${item.nameSnapshot} x${item.quantity}'),
                  if (order.note != null && order.note!.isNotEmpty) Text('หมายเหตุ: ${order.note}'),
                  const SizedBox(height: 4),
                  Text(formatBaht(order.totalCents), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (nextOptions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        // ปุ่ม "ยกเลิก" ใช้สไตล์ outline แยกจากปุ่มเดินหน้าสถานะปกติ
                        for (final next in nextOptions)
                          if (next == OrderStatus.cancelled)
                            OutlinedButton(
                              onPressed: () => _advance(order, next),
                              child: Text(OrderStatus.label(next)),
                            )
                          else
                            FilledButton(
                              onPressed: () => _advance(order, next),
                              child: Text(OrderStatus.label(next)),
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
