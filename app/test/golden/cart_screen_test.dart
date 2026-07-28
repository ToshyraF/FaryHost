import 'package:flutter_test/flutter_test.dart';

import 'package:faryhost_app/core/models/menu_item.dart';
import 'package:faryhost_app/core/state/cart_state.dart';
import 'package:faryhost_app/features/customer/cart_screen.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('CartScreen ตอนตะกร้าว่าง', (tester) async {
    await pumpGolden(tester, const CartScreen());

    await expectLater(
      find.byType(CartScreen),
      matchesGoldenFile('goldens/cart_screen_empty.png'),
    );
  });

  testWidgets('CartScreen ตอนมีสินค้าในตะกร้า', (tester) async {
    final noodles = MenuItem(
      id: 'item-1',
      vendorId: 'vendor-1',
      name: 'ก๋วยเตี๋ยวเรือ',
      priceCents: 4000,
      isAvailable: true,
      createdAt: DateTime(2026, 1, 1),
    );

    final cart = CartState();
    cart.addItem('vendor-1', noodles);
    cart.addItem('vendor-1', noodles); // เพิ่มซ้ำ = จำนวน 2

    await pumpGolden(tester, const CartScreen(), cartState: cart);

    await expectLater(
      find.byType(CartScreen),
      matchesGoldenFile('goldens/cart_screen_with_items.png'),
    );
  });
}
