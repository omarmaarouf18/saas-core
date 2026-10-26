import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/features/customer/market_page.dart';
import 'package:frontend/features/customer/picker_page.dart';

import 'customer_harness.dart';

// Golden snapshots of the FE-CUST-1 pages at 360x800, light, AR-RTL and
// EN-LTR, with the bundled Plex font (like test/ui/qd_gallery_golden_test).
// Icons render as test-font boxes; map tiles are blank.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/customer/customer_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

CustomerTestDeps _deps(Locale l) {
  final deps = CustomerTestDeps();
  deps.notifications.unreadCount = 2;
  deps.marketplace.services = [
    service(id: 'svc-1', name: _t(l, 'Nile Express', 'شحن النيل')),
  ];
  deps.marketplace.nextServices = [
    service(id: 'svc-1', name: _t(l, 'Nile Express', 'شحن النيل')),
    service(
        id: 'svc-2',
        name: _t(l, 'Delta Couriers', 'مناديب الدلتا'),
        distanceKm: 4.8,
        finalPrice: 49.5),
    service(
      id: 'svc-3',
      name: _t(l, 'Night Owl', 'نايت أول'),
      distanceKm: 1.2,
      open: false,
      reopensAt: DateTime(2026, 10, 20, 9),
    ),
  ];
  deps.marketplace.nextJobs = [
    job(
      id: 'a1b2c3d4e5',
      status: 'active',
      pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
      dropNote: _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
      createdAt: DateTime(2026, 10, 19, 14, 5),
    ),
    job(
      id: 'f6e5d4c3b2',
      status: 'awaiting_price_response',
      pickupNote: null,
      dropNote: _t(l, 'Nasr City, Abbas El Akkad', 'مدينة نصر، عباس العقاد'),
      createdAt: DateTime(2026, 10, 18, 11, 40),
      price: 65,
    ),
    job(id: '9988776655', status: 'completed', price: 38),
  ];
  return deps;
}

const _pickup =
    PickedPlace(latitude: 30.05, longitude: 31.24, isDeviceLocation: true);

final Map<String, Widget Function(Locale)> _screens = {
  'home': (_) => CustomerShell(now: () => fixedNow),
  'orders': (_) => CustomerShell(initialIndex: 1, now: () => fixedNow),
  'market': (_) => CustomerMarketPage(
      category: 'delivery', pickup: _pickup, now: () => fixedNow),
  'book': (l) => CustomerBookingPage(
      service: service(name: _t(l, 'Nile Express', 'شحن النيل')),
      pickup: _pickup.copyWith(note: _t(l, 'Floor 3', 'الدور التالت'))),
  'picker': (l) => CustomerPickerPage(
      title: _t(l, 'Drop-off place', 'مكان التسليم'),
      initial: const PickedPlace(latitude: 30.06, longitude: 31.22)),
};

void main() {
  setUpAll(loadPlexFont);

  // FE-CLEANUP dark review: the shell (Home tab), dark, EN-LTR.
  testWidgets('GOLDEN customer home dark en_ltr', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(customerApp(
        _deps(en), CustomerShell(now: () => fixedNow),
        themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/cust_home_dark_en_ltr_360x800.png'));
  });

  _screens.forEach((name, build) {
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN customer $name $dir', (tester) async {
        usePhone(tester);
        await tester.pumpWidget(
            customerApp(_deps(locale), build(locale), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/cust_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
