import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/price_estimate.dart';
import 'package:frontend/models/marketplace_service.dart';

MarketplaceService service({
  double base = 20,
  double tenantBase = 25,
  double perKm = 5,
}) =>
    MarketplaceService(
      id: 'svc-1',
      tenantId: 'tenant-1',
      name: 'Nile Express',
      category: 'delivery',
      basePrice: base,
      tenantBasePrice: tenantBase,
      tenantPricePerKM: perKm,
      latitude: 30.05,
      longitude: 31.24,
      distanceKM: 0,
      finalPrice: 0,
    );

void main() {
  test('haversine: zero for the same point, ~111.2 km per degree', () {
    expect(haversineKm(30, 31, 30, 31), 0);
    expect(haversineKm(0, 0, 1, 0), closeTo(111.19, 0.01));
  });

  test('tenant base + km × rate, rounded to piasters', () {
    final svc = service(base: 20, tenantBase: 25, perKm: 5);
    final e = estimateTripPrice(
        service: svc, fromLat: 0, fromLon: 0, toLat: 0.1, toLon: 0);
    final km = haversineKm(0, 0, 0.1, 0);
    expect(e.base, 25);
    expect(e.ratePerKm, 5);
    expect(e.distanceKm, km);
    expect(e.distanceCost, (km * 5 * 100).round() / 100);
    expect(e.total, ((25 + km * 5) * 100).round() / 100);
  });

  test('falls back to the service base price when the tenant has none', () {
    final svc = service(base: 20, tenantBase: 0, perKm: 3);
    expect(baseFareOf(svc), 20);
    final e = estimateTripPrice(
        service: svc, fromLat: 30, fromLon: 31, toLat: 30, toLon: 31);
    expect(e.total, 20);
    expect(e.distanceCost, 0);
  });

  test('same formula as the old booking dialog', () {
    // Old _BookingDialog: ((base + dist * rate) * 100).round() / 100.
    final svc = service(tenantBase: 12.5, perKm: 4.75);
    const from = (30.0444, 31.2357), to = (30.0626, 31.2497);
    final dist = haversineKm(from.$1, from.$2, to.$1, to.$2);
    final e = estimateTripPrice(
        service: svc,
        fromLat: from.$1,
        fromLon: from.$2,
        toLat: to.$1,
        toLon: to.$2);
    expect(e.total, ((12.5 + dist * 4.75) * 100).round() / 100);
  });
}
