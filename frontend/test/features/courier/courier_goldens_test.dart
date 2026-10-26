import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/courier/courier_shell.dart';
import 'package:frontend/features/courier/jobs_page.dart';
import 'package:frontend/features/courier/task_page.dart';
import 'package:frontend/models/job.dart';

import 'courier_harness.dart';

// Golden snapshots of the FE-COURIER pages, 360x800, light, AR-RTL and
// EN-LTR (plus the shell and the current job in dark, EN-LTR), with the
// bundled Plex font. Regenerate with:
//   flutter test --update-goldens test/features/courier/courier_goldens_test.dart

String _t(Locale l, String en, String ar) => l.languageCode == 'ar' ? ar : en;

JobStatusHistoryEntry _at(String status, Duration ago) =>
    JobStatusHistoryEntry(status: status, at: courierNow.subtract(ago));

Job _active(Locale l, {String sub = 'picked_up', String? request}) =>
    courierJob(
      subStatus: sub,
      requestStatus: request,
      pickupAddress: _t(l, '15 Qasr El Nil St', '15 شارع قصر النيل'),
      pickupNote: _t(l, 'Third floor', 'الدور التالت'),
      dropAddress: _t(l, '4 Tahrir St, Dokki', '4 شارع التحرير، الدقي'),
      dropNote: _t(l, 'Next to Dokki metro', 'جنب مترو الدقي'),
      recipient: JobRecipient(
        name: _t(l, 'Mahmoud', 'محمود'),
        phone: '+201012345678',
        notes: _t(l, 'Call before arriving', 'كلمني قبل ما توصل'),
      ),
      package: JobPackageDetails(
          size: 'small', notes: _t(l, 'Documents', 'ورق ومستندات')),
    );

typedef _Setup = void Function(CourierTestDeps deps, Locale locale);
typedef _Act = Future<void> Function(WidgetTester tester);

Future<void> _golden(
  WidgetTester tester,
  String name,
  Locale locale,
  Widget page, {
  _Setup? setup,
  _Act? act,
  CourierTestDeps? deps,
  bool withController = true,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  usePhone(tester);
  final d = deps ?? CourierTestDeps();
  d.notifications.notifications = [notification('n1', type: 'chat')];
  setup?.call(d, locale);
  if (withController) await d.controller.refresh();
  await tester.pumpWidget(courierApp(d, page,
      locale: locale, withController: withController, themeMode: themeMode));
  await tester.pumpAndSettle();
  if (act != null) await act(tester);
  final dir = (themeMode == ThemeMode.dark ? 'dark_' : '') +
      (locale.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr');
  await expectLater(find.byType(MaterialApp),
      matchesGoldenFile('goldens/cour_${name}_${dir}_360x800.png'));
}

void main() {
  setUpAll(loadPlexFont);

  // FE-CLEANUP dark review: the shell and the current job, dark, EN-LTR.
  testWidgets('GOLDEN idle dark en_ltr', (tester) async {
    await _golden(
      tester,
      'idle',
      const Locale('en'),
      CourierShell(now: () => courierNow),
      withController: false,
      themeMode: ThemeMode.dark,
      deps: CourierTestDeps(
          auth: FakeCourierAuth(kyeStatus: 'pending_super_admin_approval')),
    );
  });

  testWidgets('GOLDEN active deliver dark en_ltr', (tester) async {
    await _golden(
        tester, 'active_deliver', const Locale('en'), const CourierTaskPage(),
        themeMode: ThemeMode.dark, setup: (d, l) {
      d.location.lastKnownPosition = position(30.0500, 31.2300);
      d.jobs.seed([_active(l, request: 'pending')]);
    });
  });

  for (final l in bothLocales) {
    final dir = l.languageCode == 'ar' ? 'ar_rtl' : 'en_ltr';

    testWidgets('GOLDEN offer $dir', (tester) async {
      await _golden(tester, 'offer', l, const CourierTaskPage(), setup: (d, l) {
        d.location.lastKnownPosition = position(30.0500, 31.2400);
        d.jobs.seed([
          courierJob(
            status: 'pending_dispatch',
            offerExpiresAt: courierNow.add(const Duration(seconds: 25)),
            pickupAddress: _t(l, '15 Qasr El Nil St', '15 شارع قصر النيل'),
            pickupNote: _t(l, 'Third floor', 'الدور التالت'),
            dropNote:
                _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
            package: JobPackageDetails(
                size: 'small', notes: _t(l, 'Documents', 'ورق ومستندات')),
          ),
        ]);
      });
    });

    testWidgets('GOLDEN active pickup $dir', (tester) async {
      await _golden(tester, 'active_pickup', l, const CourierTaskPage(),
          setup: (d, l) {
        d.location.lastKnownPosition = position(30.0400, 31.2300);
        d.jobs.seed([_active(l, sub: 'heading_to_pickup')]);
      });
    });

    testWidgets('GOLDEN active deliver $dir', (tester) async {
      await _golden(tester, 'active_deliver', l, const CourierTaskPage(),
          setup: (d, l) {
        d.location.lastKnownPosition = position(30.0500, 31.2300);
        d.jobs.seed([_active(l, request: 'pending')]);
      });
    });

    testWidgets('GOLDEN negotiation $dir', (tester) async {
      await _golden(tester, 'negotiation', l, const CourierTaskPage(),
          setup: (d, l) {
        d.jobs.seed([
          courierJob(
            status: 'awaiting_price_response',
            proposed: 38,
            proposedBy: 'customer',
            proposalExpiresAt: courierNow.add(const Duration(minutes: 3)),
            dropNote: _t(l, 'Zamalek', 'الزمالك'),
            pickupNote: _t(l, 'Beside the kiosk', 'جنب الكشك'),
          ),
        ]);
      });
    });

    testWidgets('GOLDEN complete sheet $dir', (tester) async {
      await _golden(tester, 'complete_sheet', l, const CourierTaskPage(),
          setup: (d, l) => d.jobs.seed([_active(l)]),
          act: (tester) async {
            await tester.tap(find.byKey(const Key('courier_action_deliver')));
            await tester.pumpAndSettle();
            await tester
                .tap(find.byKey(const Key('courier_complete_different')));
            await tester.pumpAndSettle();
          });
    });

    testWidgets('GOLDEN cancel sheet $dir', (tester) async {
      await _golden(tester, 'cancel_sheet', l, const CourierTaskPage(),
          setup: (d, l) => d.jobs.seed([_active(l)]),
          act: (tester) async {
            await tester.tap(find.byKey(const Key('courier_request_cancel')));
            await tester.pumpAndSettle();
          });
    });

    testWidgets('GOLDEN idle $dir', (tester) async {
      await _golden(
        tester,
        'idle',
        l,
        CourierShell(now: () => courierNow),
        withController: false,
        deps: CourierTestDeps(
            auth: FakeCourierAuth(kyeStatus: 'pending_super_admin_approval')),
      );
    });

    testWidgets('GOLDEN my jobs $dir', (tester) async {
      await _golden(tester, 'jobs', l, const CourierJobsPage(),
          deps: CourierTestDeps(auth: FakeCourierAuth(kyeStatus: null)),
          setup: (d, l) {
        d.jobs.seed([
          courierJob(
              id: 'j1',
              status: 'completed',
              dropNote:
                  _t(l, 'Zamalek, 26th of July St', 'الزمالك، شارع 26 يوليو'),
              history: [_at('completed', const Duration(hours: 1))]),
          courierJob(
              id: 'j2',
              status: 'completed',
              price: 35,
              dropNote: _t(l, 'Dokki', 'الدقي'),
              history: [_at('completed', const Duration(hours: 3))]),
          courierJob(
              id: 'j3',
              status: 'cancelled',
              dropNote: _t(l, 'Mohandessin', 'المهندسين'),
              cancelReason: _t(l, 'Bike broke down', 'الموتوسيكل عطل'),
              history: [_at('cancelled', const Duration(hours: 4))]),
        ]);
      });
    });

    testWidgets('GOLDEN blocked $dir', (tester) async {
      await _golden(
        tester,
        'blocked',
        l,
        CourierShell(now: () => courierNow),
        withController: false,
        deps: CourierTestDeps(
            auth: FakeCourierAuth(
                accountStatus: 'suspended',
                suspensionReason: _t(l, 'Repeated customer complaints',
                    'شكاوى متكررة من العملاء'))),
      );
    });

    testWidgets('GOLDEN account $dir', (tester) async {
      await _golden(tester, 'account', l, const AccountPage(),
          deps: CourierTestDeps(
              auth:
                  FakeCourierAuth(kyeStatus: 'pending_super_admin_approval')));
    });
  }
}
