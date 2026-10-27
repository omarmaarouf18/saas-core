import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/market_page.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/models/saved_address.dart';

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

CustomerTestDeps _pickerSaved(Locale l) {
  final deps = CustomerTestDeps();
  final saved = [
    SavedAddress(
      id: 'addr-home',
      label: 'Home',
      address: _t(l, '12 Tahrir St, Dokki', '12 شارع التحرير، الدقي'),
      addressNote:
          _t(l, 'Floor 3, the blue door', 'الدور التالت، الباب الأزرق'),
      latitude: 30.0444,
      longitude: 31.2357,
    ),
    SavedAddress(
      id: 'addr-work',
      label: 'Work',
      address: _t(l, 'Smart Village B7', 'القرية الذكية B7'),
      latitude: 30.075,
      longitude: 31.02,
    ),
  ];
  deps.auth.user = deps.auth.user!.copyWith(
    savedAddresses: saved,
    frequentAddresses: [
      for (final a in saved) a.address,
      _t(l, 'Club, Heliopolis', 'النادي، مصر الجديدة'),
    ],
  );
  return deps;
}

final Map<String, (CustomerTestDeps Function(Locale), Widget Function(Locale))>
    _cases = {
  'picker_saved': (
    _pickerSaved,
    (l) => CustomerPickerPage(
        title: _t(l, 'Drop-off place', 'مكان التسليم'),
        initial: const PickedPlace(latitude: 30.06, longitude: 31.22)),
  ),
  'market_photo': (
    _marketPhotos,
    (_) => CustomerMarketPage(
        category: 'delivery', pickup: _pickup, now: () => fixedNow),
  ),
};

final Set<String> _dark = {'market_photo', 'picker_saved'};

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
