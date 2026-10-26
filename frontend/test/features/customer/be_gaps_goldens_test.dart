import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/market_page.dart';

import '../../helpers/fake_service_photos.dart';
import 'customer_harness.dart';

// FE-BE-GAPS goldens at 360x800 with the Plex font: light AR-RTL and
// EN-LTR, plus one dark EN-LTR per new state.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/customer/be_gaps_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

const _pickup =
    PickedPlace(latitude: 30.05, longitude: 31.24, isDeviceLocation: true);

CustomerTestDeps _marketPhotos(Locale l) {
  final deps = CustomerTestDeps(
      photos:
          FakeServicePhotoStore(photos: {'svc-1': solidPng(48, 40, 110, 190)}));
  deps.marketplace.nextServices = [
    service(
        id: 'svc-1',
        name: _t(l, 'Nile Express', 'شحن النيل'),
        photoUrl: 'services/svc-1/photo.png'),
    service(
        id: 'svc-2',
        name: _t(l, 'Delta Couriers', 'مناديب الدلتا'),
        distanceKm: 4.8),
  ];
  return deps;
}

final Map<String, (CustomerTestDeps Function(Locale), Widget Function(Locale))>
    _cases = {
  'market_photo': (
    _marketPhotos,
    (_) => CustomerMarketPage(
        category: 'delivery', pickup: _pickup, now: () => fixedNow),
  ),
};

final Set<String> _dark = {'market_photo'};

void main() {
  setUpAll(loadPlexFont);

  _cases.forEach((name, c) {
    final variants = [
      for (final l in bothLocales)
        (l, ThemeMode.light, l == ar ? 'ar_rtl' : 'en_ltr'),
      if (_dark.contains(name)) (en, ThemeMode.dark, 'dark_en_ltr'),
    ];
    for (final (locale, mode, dir) in variants) {
      testWidgets('GOLDEN customer $name $dir', (tester) async {
        usePhone(tester);
        await tester.pumpWidget(customerApp(c.$1(locale), c.$2(locale),
            locale: locale, themeMode: mode));
        await tester.pumpAndSettle();
        await precacheShownImages(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/cust_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
