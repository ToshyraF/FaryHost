class MenuItem {
  final String id;
  final String vendorId;
  final String name;
  final String? description;
  final int priceCents;
  final bool isAvailable;
  final DateTime createdAt;

  MenuItem({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.priceCents,
    required this.isAvailable,
    required this.createdAt,
    this.description,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      vendorId: json['vendor_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceCents: json['price_cents'] as int,
      isAvailable: json['is_available'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
