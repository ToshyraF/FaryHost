/// รายการสินค้า 1 ชิ้นในออเดอร์ — ชื่อ/ราคาเป็น "snapshot" ณ ตอนสั่ง
/// (ไม่ใช่ราคาปัจจุบันของเมนู) เพื่อให้ตรงกับยอดเงินที่ลูกค้าจ่ายจริงตอนนั้น
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

/// คัดลอกมาจาก backend/internal/models.OrderStatus/NextStatuses ด้วยมือ
/// (ไม่มี code generation) ถ้าฝั่ง backend แก้ ต้องมาแก้ที่นี่ด้วยให้ตรงกัน
class OrderStatus {
  static const awaitingPayment = 'awaiting_payment'; // สร้างออเดอร์แล้ว รอลูกค้าสแกน QR จ่ายเงิน
  static const pending = 'pending'; // จ่ายเงินสำเร็จแล้ว รอร้านค้ากดรับ
  static const accepted = 'accepted'; // ร้านค้ารับออเดอร์แล้ว
  static const preparing = 'preparing'; // กำลังทำอาหาร
  static const ready = 'ready'; // พร้อมให้มารับ
  static const completed = 'completed'; // รับของแล้ว (จบ)
  static const cancelled = 'cancelled'; // ยกเลิก (จบ)

  /// จากสถานะปัจจุบัน (key) ร้านค้าเปลี่ยนไปสถานะไหนต่อได้บ้าง (value)
  /// ต้องตรงกับ backend/internal/models.NextStatuses เป๊ะๆ
  ///
  /// awaitingPayment -> pending ไม่ใช่การกระทำของร้านค้า (ระบบเปลี่ยนให้เอง
  /// อัตโนมัติทันทีที่ backend ยืนยันกับ Omise ได้ว่าจ่ายเงินสำเร็จ) จึงไม่มี
  /// ปุ่มให้กดในแอปฝั่งร้านค้า มีแค่ปุ่มยกเลิกออเดอร์ที่ยังไม่จ่ายเงินเท่านั้น
  static const Map<String, List<String>> nextStatuses = {
    awaitingPayment: [cancelled],
    pending: [accepted, cancelled],
    accepted: [preparing, cancelled],
    preparing: [ready, cancelled],
    ready: [completed],
  };

  /// แปลงสถานะเป็นข้อความภาษาไทยให้ผู้ใช้อ่านเข้าใจง่าย
  static String label(String status) {
    switch (status) {
      case awaitingPayment:
        return 'รอชำระเงิน';
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

/// คำสั่งซื้อ 1 ออเดอร์ (สั่งได้ทีละร้านค้าเดียวเท่านั้น)
/// การจ่ายเงินเป็นแบบบังคับผ่าน Omise PromptPay QR ไม่มีทางเลือกจ่ายเงินสด
/// หน้าร้านแล้ว
class Order {
  final String id;
  final String code; // รหัสสั้นๆ ที่ลูกค้าโชว์หน้าร้านตอนมารับอาหาร
  final String customerId;
  final String vendorId;
  final String status;
  final int totalCents;
  final String? note;
  final List<OrderItem> items;
  final String? paymentQRCodeUri; // มีค่าเฉพาะตอนสถานะเป็น OrderStatus.awaitingPayment
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
    this.paymentQRCodeUri,
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
      paymentQRCodeUri: json['payment_qr_code_uri'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
