import 'package:flutter/foundation.dart';

import '../models/menu_item.dart';

class CartLine {
  final MenuItem menuItem;
  final int quantity;

  CartLine(this.menuItem, this.quantity);

  int get subtotalCents => menuItem.priceCents * quantity;
}

/// An order is always placed with a single stall, so the cart only ever
/// holds lines from one vendor at a time. Adding an item from a different
/// vendor clears whatever was there before.
class CartState extends ChangeNotifier {
  String? _vendorId;
  final Map<String, CartLine> _lines = {};
  String note = '';

  String? get vendorId => _vendorId;
  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int get totalCents => _lines.values.fold(0, (sum, l) => sum + l.subtotalCents);
  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);

  bool belongsToOtherVendor(String vendorId) => _vendorId != null && _vendorId != vendorId;

  void addItem(String vendorId, MenuItem item) {
    if (belongsToOtherVendor(vendorId)) {
      clear();
    }
    _vendorId = vendorId;
    final existing = _lines[item.id];
    _lines[item.id] = CartLine(item, (existing?.quantity ?? 0) + 1);
    notifyListeners();
  }

  void setQuantity(String menuItemId, int quantity) {
    final existing = _lines[menuItemId];
    if (existing == null) return;
    if (quantity <= 0) {
      _lines.remove(menuItemId);
    } else {
      _lines[menuItemId] = CartLine(existing.menuItem, quantity);
    }
    if (_lines.isEmpty) _vendorId = null;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    _vendorId = null;
    note = '';
    notifyListeners();
  }

  List<Map<String, dynamic>> toOrderItems() {
    return _lines.values
        .map((l) => {'menu_item_id': l.menuItem.id, 'quantity': l.quantity})
        .toList();
  }
}
