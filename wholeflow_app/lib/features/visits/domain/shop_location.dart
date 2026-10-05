/// A shop's pin (`shop_locations`): check-ins must be within [radiusM] of it.
class ShopLocation {
  const ShopLocation({
    required this.shopId,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    this.fromSuggestion = false,
    this.setAt,
  });

  factory ShopLocation.fromJson(Map<String, dynamic> json) => ShopLocation(
    shopId: json['shop_id'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radiusM: (json['radius_m'] as num).toInt(),
    fromSuggestion: json['source'] == 'suggestion',
    setAt: json['set_at'] == null ? null : DateTime.tryParse(json['set_at'] as String)?.toLocal(),
  );

  static const columns = 'shop_id,latitude,longitude,radius_m,source,set_at';

  /// Allowed radius range and default, as the database enforces.
  static const minRadius = 5;

  /// Below this, everyday phone GPS (often ±10–20 m) may refuse staff who are inside.
  static const preciseRadius = 20;
  static const maxRadius = 2000;
  static const defaultRadius = 100;

  final String shopId;
  final double latitude;
  final double longitude;
  final int radiusM;
  final bool fromSuggestion;
  final DateTime? setAt;
}

/// Where a staff member was when they checked in at a shop with no pin.
class LocationSuggestion {
  const LocationSuggestion({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.accuracyM,
    this.staffName,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) => LocationSuggestion(
    id: json['id'] as String,
    shopId: json['shop_id'] as String,
    shopName: ((json['shops'] as Map?)?['name'] as String?) ?? 'Shop',
    staffName: (json['users'] as Map?)?['name'] as String?,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  static const columns = 'id,shop_id,latitude,longitude,accuracy_m,created_at,shops(name),users!suggested_by(name)';

  final String id;
  final String shopId;
  final String shopName;
  final String? staffName;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final DateTime createdAt;
}
