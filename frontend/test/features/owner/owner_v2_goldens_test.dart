import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/order_detail_page.dart';
import 'package:frontend/models/job.dart';

import 'owner_harness.dart';

// FE-V2-CONSUME goldens: owner order detail with the recipient, package,
// phase chip and ETA, and scrolled to the history timeline, 360x800,
// light, AR-RTL and EN-LTR, Plex font.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/owner/owner_v2_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

DateTime _ago(int m) => ownerNow.subtract(Duration(minutes: m));

Job _job(Locale l) => ownerJob(
      subStatus: 'picked_up',
      createdAt: _ago(40),
      history: [
        JobStatusHistoryEntry(status: 'pending_dispatch', at: _ago(40)),
        JobStatusHistoryEntry(
            status: 'active', subStatus: 'heading_to_pickup', at: _ago(38)),
        JobStatusHistoryEntry(
            status: 'active', subStatus: 'picked_up', at: _ago(10)),
      ],
      etaMinutes: 25,
      courierPhone: '+201098765432',
      pickupNote: _t(l, 'Floor 3', 'الدور التالت'),
      dropNote: _t(l, 'Beside the metro', 'جنب المترو'),
      pickupAddress: _t(l, '15 Kasr El Nil St', '15 شارع قصر النيل'),
      dropAddress: _t(l, '4 Tahrir St, Dokki', '4 شارع التحرير، الدقي'),
      recipient: JobRecipient(
          name: _t(l, 'Mahmoud', 'محمود'),
          phone: '+201012345678',
          notes: _t(l, 'Ring twice', 'اضرب الجرس مرتين')),
      package: JobPackageDetails(
          size: 'large', notes: _t(l, 'Glass, fragile', 'إزاز، قابل للكسر')),
    );

void main() {
  setUpAll(loadPlexFont);

  for (final scroll in [false, true]) {
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      final name = scroll ? 'own_order_v2_timeline' : 'own_order_v2';
      testWidgets('GOLDEN $name $dir', (tester) async {
        usePhone(tester);
        final deps = OwnerTestDeps();
        deps.owner.nextJobs = [_job(locale)];
        deps.owner.nextEmployees = [
          staff('emp-1', _t(locale, 'Karim', 'كريم'))
        ];
        await pumpOwner(
            tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'),
            locale: locale);
        if (scroll) {
          await tester.scrollUntilVisible(
              find.byKey(const Key('own_order_timeline')), 100,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${dir}_360x800.png'),
        );
      });
    }
  }
}
