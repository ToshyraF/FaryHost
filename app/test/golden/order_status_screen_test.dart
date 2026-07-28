import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:faryhost_app/core/api_client.dart';
import 'package:faryhost_app/features/customer/order_status_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('OrderStatusScreen แสดงรหัสรับอาหารและรายการสินค้า', (tester) async {
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/orders/order-1')) {
          return http.Response(
            jsonEncode({
              'id': 'order-1',
              'code': 'K7X4Q9',
              'customer_id': 'user-1',
              'vendor_id': 'vendor-1',
              'status': 'accepted',
              'total_cents': 8000,
              'note': 'เผ็ดน้อย',
              'items': [
                {
                  'menu_item_id': 'item-1',
                  'name_snapshot': 'ก๋วยเตี๋ยวเรือ',
                  'price_cents': 4000,
                  'quantity': 2,
                  'subtotal_cents': 8000,
                },
              ],
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:05:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await pumpGolden(tester, const OrderStatusScreen(orderId: 'order-1'), apiClient: client);

    await expectLater(
      find.byType(OrderStatusScreen),
      matchesGoldenFile('goldens/order_status_screen.png'),
    );

    // OrderStatusScreen ตั้ง Timer.periodic ไว้ (poll สถานะทุก 5 วิ) ต้อง
    // unmount widget ก่อนจบเทสเพื่อให้ dispose() ยกเลิก timer ไม่งั้น
    // test framework จะ fail ว่ามี timer ค้างอยู่ตอนจบเทส
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
