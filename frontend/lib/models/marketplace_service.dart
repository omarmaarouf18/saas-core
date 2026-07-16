class MarketplaceService {
  final String id;
  final String tenantId;
  final String name;
  final String category;
  final double basePrice;
  final double tenantBasePrice;
  final double tenantPricePerKM;
  final double latitude;
  final double longitude;
  final double distanceKM;
  final double finalPrice;

  MarketplaceService({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.category,
    required this.basePrice,
    required this.tenantBasePrice,
    required this.tenantPricePerKM,
    required this.latitude,
    required this.longitude,
    required this.distanceKM,
    required this.finalPrice,
  });

  factory MarketplaceService.fromJson(Map<String, dynamic> json) {
    // Dynamic pricing structure returns service data inside a nested object or flattened
    final serviceJson = json['id'] != null ? json : (json['Service'] ?? json);
    return MarketplaceService(
      id: serviceJson['id'] ?? '',
      tenantId: serviceJson['tenant_id'] ?? '',
      name: serviceJson['name'] ?? '',
      category: serviceJson['category'] ?? '',
      basePrice: (serviceJson['base_price'] as num?)?.toDouble() ?? 0.0,
      tenantBasePrice: (serviceJson['tenant_base_price'] as num?)?.toDouble() ?? 0.0,
      tenantPricePerKM: (serviceJson['tenant_price_per_km'] as num?)?.toDouble() ?? 0.0,
      latitude: (serviceJson['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (serviceJson['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceKM: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      finalPrice: (json['final_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
