import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:faryhost_app/core/api_client.dart';
import 'package:faryhost_app/features/vendor/vendor_dashboard_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('VendorDashboardScreen แสดงฟอร์มตั้งค่าร้านตอนยังไม่เคยสร้างร้าน', (tester) async {
    // จำลอง GET /vendors/me คืน 404 เหมือน vendor user ที่ยังไม่เคยตั้งค่าร้านเลย
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/vendors/me')) {
          return http.Response(
            jsonEncode({'error': "you haven't set up a stall yet"}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await pumpGolden(
      tester,
      const VendorDashboardScreen(),
      apiClient: client,
      surfaceSize: const Size(400, 900),
    );

    await expectLater(
      find.byType(VendorDashboardScreen),
      matchesGoldenFile('goldens/vendor_create_stall_screen.png'),
    );
  });
}
