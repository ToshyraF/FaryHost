import 'menu_item.dart';

class Vendor {
  final String id;
  final String ownerUserId;
  final String name;
  final String? description;
  final String? stallNumber;
  final String? marketZone;
  final bool isOpen;
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
