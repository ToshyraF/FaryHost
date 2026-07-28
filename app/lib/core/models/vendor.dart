import 'menu_item.dart';

/// ร้านค้า/แผงขายของในตลาดนัด 1 ร้าน
class Vendor {
  final String id;
  final String ownerUserId;
  final String name;
  final String? description;
  final String? stallNumber; // เลขล็อค/แผง
  final String? marketZone; // โซนในตลาด
  final bool isOpen; // ถ้าปิด ลูกค้าจะสั่งอาหารจากร้านนี้ไม่ได้
  final DateTime createdAt;

  Vendor({
    required this.id,
    required this.ownerUserId,
    required this.name,
    required this.isOpen,
    required this.createdAt,
    this.description,
    this.stallNumber,
    this.marketZone,
  });

  factory Vendor.fromJson(Map<String, dynamic> json) {
    return Vendor(
      id: json['id'] as String,
      ownerUserId: json['owner_user_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      stallNumber: json['stall_number'] as String?,
      marketZone: json['market_zone'] as String?,
      isOpen: json['is_open'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// ข้อมูลร้านค้าแบบละเอียด (ร้านค้า + เมนูทั้งหมด) ที่ได้จาก endpoint
/// GET /api/vendors/{id} — ใช้ตอนลูกค้าเปิดดูหน้าเมนูของร้าน
class VendorDetail extends Vendor {
  final List<MenuItem> menuItems;

  VendorDetail({
    required super.id,
    required super.ownerUserId,
    required super.name,
    required super.isOpen,
    required super.createdAt,
    required this.menuItems,
    super.description,
    super.stallNumber,
    super.marketZone,
  });

  factory VendorDetail.fromJson(Map<String, dynamic> json) {
    final vendor = Vendor.fromJson(json);
    final items = (json['menu_items'] as List<dynamic>? ?? [])
        .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return VendorDetail(
      id: vendor.id,
      ownerUserId: vendor.ownerUserId,
      name: vendor.name,
      description: vendor.description,
      stallNumber: vendor.stallNumber,
      marketZone: vendor.marketZone,
      isOpen: vendor.isOpen,
      createdAt: vendor.createdAt,
      menuItems: items,
    );
  }
}
