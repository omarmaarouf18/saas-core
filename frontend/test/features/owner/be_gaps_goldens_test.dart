import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/order_detail_page.dart';
import 'package:frontend/features/owner/orders_page.dart';
import 'package:frontend/features/owner/service_setup_page.dart';
import 'package:frontend/features/owner/team_page.dart';

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
  bool refresh,
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

void _people(OwnerTestDeps deps, Locale l) {
  deps.owner.nextEmployees = [
    {
      ...staff('emp-1', _t(l, 'Karim', 'كريم')),
      'kye_status': 'approved',
    },
    {
      ...staff('emp-2', _t(l, 'Sara', 'سارة')),
      'kye_status': 'pending_super_admin_approval',
    },
    {
      ...staff('emp-3', _t(l, 'Hany', 'هاني'), active: false),
      'kye_status': 'rejected',
    },
    {...staff('emp-4', _t(l, 'Omar', 'عمر')), 'kye_status': 'none'},
  ];
  deps.owner.nextJobs = [
    ownerJob(
      id: 'named-0001',
      employeeId: 'emp-1',
      dropNote: _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
      pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
    ),
    ownerJob(
      id: 'legacy-001',
      employeeId: 'emp-2',
      userId: 'cust-abcdef',
      dropNote: _t(l, 'Nasr City, Abbas El Akkad', 'مدينة نصر، عباس العقاد'),
    ),
  ];
  deps.owner.nextJobJson = {
    'named-0001': {
      'id': 'named-0001',
      'customer_name': _t(l, 'Mona Ali', 'منى علي'),
    },
  };
}

final Map<String, _Case> _cases = {
  'service_photo': (
    page: () => const OwnerServicePage(),
    setup: _servicePhoto,
    refresh: false,
  ),
  'order_customer': (
    page: () => const OwnerOrderDetailPage(jobId: 'named-0001'),
    setup: _people,
    refresh: true,
  ),
  'orders_customer': (
    page: () => const Scaffold(body: OwnerOrdersPage()),
    setup: _people,
    refresh: true,
  ),
  'team_kye': (
    page: () => const Scaffold(body: OwnerTeamPage()),
    setup: _people,
    refresh: true,
  ),
};

final Set<String> _dark = {
  'service_photo',
  'order_customer',
  'orders_customer',
  'team_kye',
};

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
            locale: locale, refresh: c.refresh, themeMode: mode);
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
