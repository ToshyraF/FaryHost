import 'package:flutter/foundation.dart';

import '../models/menu_item.dart';

/// รายการสินค้า 1 บรรทัดในตะกร้า (เมนู + จำนวนที่สั่ง)
class CartLine {
  final MenuItem menuItem;
  final int quantity;

  CartLine(this.menuItem, this.quantity);

  int get subtotalCents => menuItem.priceCents * quantity;
}

/// ตะกร้าสินค้า — เนื่องจาก 1 ออเดอร์สั่งได้แค่ร้านเดียว ตะกร้านี้จึงเก็บสินค้า
/// จากร้านเดียวได้ทีละร้านเท่านั้น ถ้าเพิ่มสินค้าจากร้านอื่นเข้ามา จะล้าง
/// ตะกร้าเดิมทิ้งก่อนอัตโนมัติ
class CartState extends ChangeNotifier {
  String? _vendorId;
  final Map<String, CartLine> _lines = {};
  String note = '';

  String? get vendorId => _vendorId;
  List<CartLine> get lines => _lines.values.toList();
  bool get isEmpty => _lines.isEmpty;
  int get totalCents => _lines.values.fold(0, (sum, l) => sum + l.subtotalCents);
  int get itemCount => _lines.values.fold(0, (sum, l) => sum + l.quantity);

  /// true ถ้าตะกร้อนี้มีของจากร้านอื่น (ไม่ใช่ vendorId ที่ระบุ) ค้างอยู่
  bool belongsToOtherVendor(String vendorId) => _vendorId != null && _vendorId != vendorId;

  /// เพิ่มสินค้าเข้าตะกร้า ถ้าตะกร้อเดิมเป็นของร้านอื่น จะล้างของเก่าทิ้งก่อน
  void addItem(String vendorId, MenuItem item) {
    if (belongsToOtherVendor(vendorId)) {
      clear();
    }
    _vendorId = vendorId;
    final existing = _lines[item.id];
    _lines[item.id] = CartLine(item, (existing?.quantity ?? 0) + 1);
    notifyListeners();
  }

  /// ปรับจำนวนสินค้าในตะกร้า ถ้าลดจนเหลือ 0 หรือติดลบ จะเอาออกจากตะกร้าไปเลย
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

  /// แปลงตะกร้าเป็นรูปแบบที่ POST /api/orders ต้องการ (menu_item_id + quantity)
  List<Map<String, dynamic>> toOrderItems() {
    return _lines.values
        .map((l) => {'menu_item_id': l.menuItem.id, 'quantity': l.quantity})
        .toList();
  }
}
