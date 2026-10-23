import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/job.dart';

import '../customer_harness.dart';
import 'order_harness.dart';
import 'order_v2_fixtures.dart';

// FE-V2-CONSUME goldens: the customer order page with job model v2 fields
// (phase, ETA, call button, history timeline; then the route card with
// address text, recipient and package), 360x800, light, AR-RTL and
// EN-LTR, Plex font. Map tiles are blank.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/customer/order/order_v2_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

Job _job(Locale l, {String status = 'active', String? sub = 'picked_up'}) =>
    orderJobV2(
      status: status,
      subStatus: sub,
      courierPhone: status == 'active' ? '+201098765432' : null,
      pickupAddress: _t(l, '15 Kasr El Nil St', '15 شارع قصر النيل'),
      dropAddress: _t(l, '4 Tahrir St, Dokki', '4 شارع التحرير، الدقي'),
      pickupNote: _t(l, 'Floor 3', 'الدور التالت'),
      dropNote: _t(l, 'Beside the metro', 'جنب المترو'),
      recipient: JobRecipient(
          name: _t(l, 'Mahmoud', 'محمود'),
          phone: '+201012345678',
          notes: _t(l, 'Call before arriving', 'كلّمه قبل ما توصل')),
      package: JobPackageDetails(
          size: 'small', notes: _t(l, 'Documents', 'أوراق ومستندات')),
    );

void main() {
  setUpAll(loadPlexFont);

  final cases = <String, (Job Function(Locale), bool)>{
    // (job, scroll to the route card)
    'active': ((l) => _job(l), false),
    'active_details': ((l) => _job(l), true),
    'completed': ((l) => _job(l, status: 'completed', sub: null), false),
  };

  cases.forEach((name, c) {
    final (build, scroll) = c;
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN order v2 $name $dir', (tester) async {
        final deps = CustomerTestDeps();
        deps.marketplace.services = [
          service(name: _t(locale, 'Nile Express', 'شحن النيل')),
        ];
        deps.map.setCourier(30.055, 31.232);
        await pumpOrder(tester, deps, build(locale),
            locale: locale,
            lookup: FakeCourierLookup({'emp-1': _t(locale, 'Karim', 'كريم')}));
        if (scroll) {
          await tester.scrollUntilVisible(
              find.byKey(const Key('job_package')), 100,
              scrollable: find.descendant(
                  of: find.byKey(const Key('ord_list')),
                  matching: find.byType(Scrollable)));
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/ord_v2_${name}_${dir}_360x800.png'),
        );
        await unmountOrder(tester, deps);
      });
    }
  });
}
