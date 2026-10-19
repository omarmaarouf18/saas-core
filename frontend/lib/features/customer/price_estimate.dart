import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/marketplace_service.dart';

/// Client-side trip price estimate, the formula the old booking dialog used:
/// (tenant base price, or the service base price when the tenant has none)
/// + straight-line km × tenant price per km, rounded to piasters. The server
/// prices the job itself; this is only shown as "about X".
@immutable
class PriceEstimate {
  const PriceEstimate({
    required this.base,
    required this.ratePerKm,
    required this.distanceKm,
    required this.distanceCost,
    required this.total,
  });

  final double base;
  final double ratePerKm;
  final double distanceKm;
  final double distanceCost;
  final double total;
}

double _round2(double v) => (v * 100).round() / 100;

/// Great-circle distance in km (earth radius 6371 km).
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// The opening fee used by [estimateTripPrice].
double baseFareOf(MarketplaceService service) =>
    service.tenantBasePrice > 0 ? service.tenantBasePrice : service.basePrice;

PriceEstimate estimateTripPrice({
  required MarketplaceService service,
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
}) {
  final base = baseFareOf(service);
  final rate = service.tenantPricePerKM;
  final dist = haversineKm(fromLat, fromLon, toLat, toLon);
  return PriceEstimate(
    base: base,
    ratePerKm: rate,
    distanceKm: dist,
    distanceCost: _round2(dist * rate),
    total: _round2(base + dist * rate),
  );
}
