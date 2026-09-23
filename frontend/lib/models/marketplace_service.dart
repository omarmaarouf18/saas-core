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
  // Owner-configured public profile fields (exposed by GET /users/services
  // via the embedded Service; nullable because older payloads omit them).
  // address/photoUrl are parsed and available but not rendered on the
  // compact marketplace card in this pass (deliberate scope limit).
  final String? workingHours;
  final double? coverageRadiusKm;
  final String? address;
  final String? photoUrl;

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
    this.workingHours,
    this.coverageRadiusKm,
    this.address,
    this.photoUrl,
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
      tenantBasePrice:
          (serviceJson['tenant_base_price'] as num?)?.toDouble() ?? 0.0,
      tenantPricePerKM:
          (serviceJson['tenant_price_per_km'] as num?)?.toDouble() ?? 0.0,
      latitude: (serviceJson['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (serviceJson['longitude'] as num?)?.toDouble() ?? 0.0,
      distanceKM: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      finalPrice: (json['final_price'] as num?)?.toDouble() ?? 0.0,
      workingHours: serviceJson['working_hours'] as String?,
      coverageRadiusKm: (serviceJson['coverage_radius_km'] as num?)?.toDouble(),
      address: serviceJson['address'] as String?,
      photoUrl: serviceJson['photo_url'] as String?,
    );
  }
}
