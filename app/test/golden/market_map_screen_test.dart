import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:faryhost_app/core/api_client.dart';
import 'package:faryhost_app/features/customer/market_map_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('MarketMapScreen แสดงตัวละครและป้ายร้านค้าบนแผนที่', (tester) async {
    final client = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/vendors')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'vendor-1',
                'owner_user_id': 'user-1',
                'name': 'ก๋วยเตี๋ยวป้าแดง',
                'stall_number': 'A12',
                'market_zone': 'โซน A',
                'is_open': true,
                'created_at': '2026-01-01T00:00:00Z',
              },
              {
                'id': 'vendor-2',
                'owner_user_id': 'user-2',
                'name': 'ส้มตำลุงหนวด',
                'stall_number': 'B03',
                'market_zone': 'โซน B',
                'is_open': false,
                'created_at': '2026-01-01T00:00:00Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await pumpGolden(tester, const MarketMapScreen(), apiClient: client);

    await expectLater(
      find.byType(MarketMapScreen),
      matchesGoldenFile('goldens/market_map_screen.png'),
    );
  });
}
