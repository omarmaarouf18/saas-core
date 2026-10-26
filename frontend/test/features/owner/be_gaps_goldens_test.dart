import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/service_setup_page.dart';

import '../../helpers/fake_service_photos.dart';
import 'owner_harness.dart';

// FE-BE-GAPS goldens at 360x800 with the Plex font: light AR-RTL and
// EN-LTR, plus one dark EN-LTR per new state.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/owner/be_gaps_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

typedef _Case = ({
  Widget Function() page,
  void Function(OwnerTestDeps deps, Locale l) setup,
});

OwnerTestDeps _depsWithPhotos() => OwnerTestDeps(
    photos:
        FakeServicePhotoStore(photos: {'svc-1': solidPng(48, 214, 160, 40)}));

void _servicePhoto(OwnerTestDeps deps, Locale l) {
  deps.owner.nextServices = [
    {
      'id': 'svc-1',
      'tenant_id': 'owner-1',
      'name': _t(l, 'Nile Express', 'نايل إكسبريس'),
      'category': 'delivery',
      'address':
          _t(l, '12 Talaat Harb St, Downtown', '12 شارع طلعت حرب، وسط البلد'),
      'coverage_radius_km': 8,
      'tenant_base_price': 20,
      'tenant_price_per_km': 4.5,
      'latitude': 30.0444,
      'longitude': 31.2357,
      'photo_url': 'services/svc-1/photo.png',
    }
  ];
}

final Map<String, _Case> _cases = {
  'service_photo': (page: () => const OwnerServicePage(), setup: _servicePhoto),
};

final Set<String> _dark = {'service_photo'};

void main() {
  setUpAll(loadPlexFont);

  _cases.forEach((name, c) {
    final variants = [
      for (final l in bothLocales)
        (l, ThemeMode.light, l.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr'),
      if (_dark.contains(name)) (en, ThemeMode.dark, 'dark_en_ltr'),
    ];
    for (final (locale, mode, dir) in variants) {
      testWidgets('GOLDEN owner $name $dir', (tester) async {
        usePhone(tester);
        final deps = _depsWithPhotos();
        c.setup(deps, locale);
        await pumpOwner(tester, deps, c.page(),
            locale: locale, refresh: false, themeMode: mode);
        await precacheShownImages(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/own_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
