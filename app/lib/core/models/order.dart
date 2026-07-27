class OrderItem {
  final String menuItemId;
  final String nameSnapshot;
  final int priceCents;
  final int quantity;
  final int subtotalCents;

  OrderItem({
    required this.menuItemId,
    required this.nameSnapshot,
    required this.priceCents,
    required this.quantity,
    required this.subtotalCents,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      menuItemId: json['menu_item_id'] as String,
      nameSnapshot: json['name_snapshot'] as String,
      priceCents: json['price_cents'] as int,
      quantity: json['quantity'] as int,
      subtotalCents: json['subtotal_cents'] as int,
    );
  }
}

/// Mirrors backend/internal/models.OrderStatus. Keep in sync with
/// backend/internal/models/models.go.
class OrderStatus {
  static const pending = 'pending';
  static const accepted = 'accepted';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  /// Mirrors backend/internal/models.NextStatuses.
  static const Map<String, List<String>> nextStatuses = {
    pending: [accepted, cancelled],
    accepted: [preparing, cancelled],
    preparing: [ready, cancelled],
    ready: [completed],
  };

  static String label(String status) {
    switch (status) {
      case pending:
        return 'รอร้านรับออเดอร์';
      case accepted:
        return 'ร้านรับออเดอร์แล้ว';
      case preparing:
        return 'กำลังเตรียม';
      case ready:
        return 'พร้อมรับที่ร้าน';
      case completed:
        return 'รับของแล้ว';
      case cancelled:
        return 'ยกเลิก';
      default:
        return status;
    }
  }
}

class Order {
  final String id;
  final String code;
  final String customerId;
  final String vendorId;
  final String status;
  final int totalCents;
  final String? note;
  final List<OrderItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  Order({
    required this.id,
    required this.code,
    required this.customerId,
    required this.vendorId,
    required this.status,
    required this.totalCents,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      code: json['code'] as String,
      customerId: json['customer_id'] as String,
      vendorId: json['vendor_id'] as String,
      status: json['status'] as String,
      totalCents: json['total_cents'] as int,
      note: json['note'] as String?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
