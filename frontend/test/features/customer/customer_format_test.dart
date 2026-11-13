import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_format.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/market_page.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/job.dart';

import 'customer_harness.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('formatAddressDetails', () {
    test('en: formats all parts, hides empty parts', () {
      expect(
          formatAddressDetails(l10n,
              building: '12', floor: '3', apartment: '7'),
          'Building 12, Floor 3, Apt 7');
      expect(
          formatAddressDetails(l10n,
              building: ' 12 ', floor: null, apartment: ' 7 '),
          'Building 12, Apt 7');
      expect(
          formatAddressDetails(l10n, building: null, floor: '2', apartment: ''),
          'Floor 2');
      expect(
          formatAddressDetails(l10n,
              building: '   ', floor: '', apartment: null),
          isNull);
    });

    test('ar: formats with Arabic comma and hides empty parts', () {
      final l10nAr = AppLocalizationsAr();
      expect(
          formatAddressDetails(l10nAr,
              building: '12', floor: '3', apartment: '7'),
          'عمارة 12، الدور 3، شقة 7');
      expect(
          formatAddressDetails(l10nAr,
              building: '12', floor: null, apartment: '7'),
          'عمارة 12، شقة 7');
      expect(
          formatAddressDetails(l10nAr, building: null, floor: '', apartment: '4'),
          'شقة 4');
    });

    test('jobPlaceLabel includes details next to address', () {
      final locWithDetails = JobLocation(
        latitude: 30,
        longitude: 31,
        address: '15 Qasr El Nil St',
        building: '12',
        floor: '3',
        apartment: '7',
        addressNote: 'Beside the kiosk',
      );
      expect(jobPlaceLabel(l10n, locWithDetails),
          '15 Qasr El Nil St · Building 12, Floor 3, Apt 7');
      expect(jobPlaceLabel(l10n, locWithDetails, withNote: true),
          '15 Qasr El Nil St · Building 12, Floor 3, Apt 7 · Beside the kiosk');
    });
  });

  group('place labels never show coordinates', () {
    test('job location: note, else "Pinned location"', () {
      expect(
          jobPlaceLabel(l10n,
              JobLocation(latitude: 30, longitude: 31, addressNote: 'Gate 3')),
          'Gate 3');
      final bare = JobLocation(latitude: 30.1234, longitude: 31.5678);
      expect(bare.addressSummary(), bare.formatCoordinates());
      expect(jobPlaceLabel(l10n, bare), 'Pinned location');
      expect(jobPlaceLabel(l10n, null), 'Pinned location');
    });

    test('picked place: device, note, pinned', () {
      const device = PickedPlace(
          latitude: 1, longitude: 2, note: 'Floor 3', isDeviceLocation: true);
      expect(placeTitle(l10n, device), 'Your current location');
      expect(placeNote(device), 'Floor 3');
      const noted = PickedPlace(latitude: 1, longitude: 2, note: ' Gate 3 ');
      expect(placeTitle(l10n, noted), 'Gate 3');
      expect(placeNote(noted), isNull);
      const pinned = PickedPlace(latitude: 1, longitude: 2, note: '  ');
      expect(placeTitle(l10n, pinned), 'Pinned location');
      expect(pinned.toJobLocation().addressNote, isNull);
    });
  });

  test('category labels and job titles', () {
    expect(categoryLabel(l10n, 'delivery'), 'Deliver an order');
    expect(categoryLabel(l10n, 'transport'), 'Ride');
    expect(categoryLabel(l10n, 'shipping'), 'Ship a parcel');
    expect(categoryLabel(l10n, null), 'Order');
    final j = job(serviceId: 'svc-9');
    expect(jobTitle(l10n, j, [service(id: 'svc-9', category: 'shipping')]),
        'Ship a parcel');
    expect(jobTitle(l10n, j, [service(id: 'other')]), 'Order');
    expect(jobRef(job(id: 'a1b2c3d4e5f6')), '#QD-A1B2C3D4');
    expect(jobRefIsolated(job(id: 'ab')), '\u2066#QD-AB\u2069');
  });

  test('job price prefers the agreed price', () {
    expect(jobPrice(job(price: 30)), 30);
    expect(jobPrice(job(price: null)), isNull);
  });

  test('km format', () {
    expect(formatKm(2.44), '2.4');
    expect(formatKm(12), '12');
    expect(formatKm(1234.5), '1,234.5');
  });

  test('progress steps', () {
    expect(jobProgressStep('pending'), 0);
    expect(jobProgressStep('pending_dispatch'), 0);
    expect(jobProgressStep('awaiting_price_response'), 0);
    expect(jobProgressStep('assigned'), 1);
    expect(jobProgressStep('active'), 2);
    expect(jobProgressStep('escrow_reconciliation_required'), 3);
  });

  group('sortMarketServices', () {
    final near = service(id: 'near', distanceKm: 1, finalPrice: 50);
    final cheap = service(id: 'cheap', distanceKm: 5, finalPrice: 20);
    final closed =
        service(id: 'closed', distanceKm: 0.5, finalPrice: 10, open: false);
    final unknown =
        service(id: 'unknown', distanceKm: 3, finalPrice: 30, open: null);

    test('nearest first, closed last', () {
      expect(
          sortMarketServices([cheap, closed, near, unknown], MarketSort.nearest)
              .map((s) => s.id),
          ['near', 'unknown', 'cheap', 'closed']);
    });

    test('cheapest: opening fee first, then price per km, closed last', () {
      // final_price points the other way on purpose: it must be ignored.
      final lowFee =
          service(id: 'lowFee', tenantBase: 10, perKm: 9, finalPrice: 99);
      final sameFeeCheapKm =
          service(id: 'cheapKm', tenantBase: 15, perKm: 2, finalPrice: 80);
      final sameFeeDearKm =
          service(id: 'dearKm', tenantBase: 15, perKm: 6, finalPrice: 1);
      final serviceBase = service(
          id: 'serviceBase', base: 12, tenantBase: 0, perKm: 1, finalPrice: 5);
      final closedCheap = service(
          id: 'closed', tenantBase: 1, perKm: 1, finalPrice: 1, open: false);
      expect(
          sortMarketServices([
            closedCheap,
            sameFeeDearKm,
            serviceBase,
            sameFeeCheapKm,
            lowFee,
          ], MarketSort.cheapest)
              .map((s) => s.id),
          ['lowFee', 'serviceBase', 'cheapKm', 'dearKm', 'closed']);
    });

    test('cheapest keeps the server order for equal tariffs', () {
      final a = service(id: 'a', finalPrice: 90);
      final b = service(id: 'b', finalPrice: 10);
      expect(sortMarketServices([a, b], MarketSort.cheapest).map((s) => s.id),
          ['a', 'b']);
    });
  });
}
