import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models/order.dart';

/// หน้าจอติดตามสถานะออเดอร์ 1 รายการ พร้อมโชว์รหัสรับอาหารตัวใหญ่ๆ
/// ให้ลูกค้าเอาไปยื่นให้ร้านค้าตอนไปรับของ
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
                  Center(
                    child: Column(
                      children: [
                        const Text('รหัสรับอาหาร'),
                        Text(
                          order.code,
                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 4),
                        ),
                        const SizedBox(height: 8),
                        Chip(label: Text(OrderStatus.label(order.status))),
                      ],
                    ),
                  ),
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
