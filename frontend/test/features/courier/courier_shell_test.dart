import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/feature_flags.dart';
import 'package:frontend/features/courier/courier_shell.dart';
import 'package:frontend/models/user_profile.dart';

import 'courier_harness.dart';

Future<void> _pumpShell(WidgetTester tester, CourierTestDeps deps,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(courierApp(deps, CourierShell(now: () => courierNow),
      locale: locale, withController: false));
  await tester.pumpAndSettle();
}

void main() {
  group('flag', () {
    test('QD_REDESIGN_COURIER is off by default', () {
      expect(kRedesignCourier, isFalse);
    });

    test('root screen: legacy when off, shell when on', () {
      const legacy = SizedBox(key: Key('legacy'));
      expect(courierRootScreen(redesign: false, legacy: () => legacy),
          same(legacy));
      final on = courierRootScreen(
          redesign: true, initialIndex: 7, legacy: () => legacy);
      expect(on, isA<CourierShell>());
      expect((on as CourierShell).initialIndex, 2);
    });
  });

  group('shell', () {
    testWidgets('refreshes on open and starts the availability heartbeat',
        (tester) async {
      final deps = CourierTestDeps();
      await _pumpShell(tester, deps);
      expect(find.byKey(const Key('courier_shell')), findsOneWidget);
      expect(deps.jobs.fetchCalls, 1);
      expect(deps.location.calls.map((c) => c.name), ['availability']);
      expect(find.byKey(const Key('courier_idle_online')), findsOneWidget);
      expect(find.text('Task'), findsWidgets);
      expect(find.text('My jobs'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('an active job is tracked', (tester) async {
      final deps = CourierTestDeps();
      deps.jobs.seed([courierJob(id: 'job-9', status: 'active')]);
      await _pumpShell(tester, deps);
      expect(deps.location.calls.single.name, 'track');
      expect(deps.location.calls.single.args['job'], 'job-9');
    });

    testWidgets('offline: the heartbeat stops and one tap goes online',
        (tester) async {
      final deps = CourierTestDeps();
      deps.location.isAvailableOnline = false;
      await _pumpShell(tester, deps);
      expect(deps.location.calls.single.name, 'stopAvailability');
      await tester.tap(find.text('Make me available'));
      await tester.pumpAndSettle();
      expect(deps.location.calls.last.name, 'setOnline');
      expect(deps.location.calls.last.args['online'], isTrue);
      expect(find.byKey(const Key('courier_idle_online')), findsOneWidget);
    });

    testWidgets('a load error shows a retry banner', (tester) async {
      final deps = CourierTestDeps();
      deps.jobs.nextFetchError = 'offline';
      await _pumpShell(tester, deps);
      expect(find.byKey(const Key('courier_load_error')), findsOneWidget);
      deps.jobs.nextFetchError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.jobs.fetchCalls, 2);
      expect(find.byKey(const Key('courier_load_error')), findsNothing);
    });

    testWidgets('a new job alert refreshes and shows a notice once',
        (tester) async {
      final deps = CourierTestDeps();
      // An alert that was already there when the app opened is ignored.
      deps.notifications.notifications = [notification('old')];
      await _pumpShell(tester, deps);
      expect(deps.jobs.fetchCalls, 1);

      deps.notifications.push(notification('n1'));
      await tester.pump();
      expect(
          find.byKey(const Key('job_alert_dispatch_snackbar')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(deps.jobs.fetchCalls, 2);

      // Another change with the same newest alert: no second refresh.
      deps.notifications.notifyListeners();
      await tester.pumpAndSettle();
      expect(deps.jobs.fetchCalls, 2);

      // A non-alert notification does nothing.
      deps.notifications.push(notification('n2', type: 'chat'));
      await tester.pumpAndSettle();
      expect(deps.jobs.fetchCalls, 2);
    });

    testWidgets('switching back to a jobs tab refreshes', (tester) async {
      final deps = CourierTestDeps();
      await _pumpShell(tester, deps);
      await tester.tap(find.text('My jobs'));
      await tester.pumpAndSettle();
      expect(deps.jobs.fetchCalls, 2);
    });

    testWidgets('the bell opens notifications', (tester) async {
      final deps = CourierTestDeps();
      await _pumpShell(tester, deps);
      await tester.tap(find.byKey(const Key('courier_bell')));
      expect(deps.nav.opened, ['notifications']);
    });
  });

  group('verification banner', () {
    testWidgets('none once approved', (tester) async {
      await _pumpShell(tester, CourierTestDeps());
      expect(find.byKey(const Key('courier_kye_missing')), findsNothing);
      expect(find.byKey(const Key('courier_kye_pending')), findsNothing);
      expect(find.byKey(const Key('courier_kye_rejected')), findsNothing);
    });

    testWidgets('missing documents open the upload', (tester) async {
      final deps = CourierTestDeps(auth: FakeCourierAuth(kyeStatus: null));
      await _pumpShell(tester, deps);
      expect(find.byKey(const Key('courier_kye_missing')), findsOneWidget);
      await tester.tap(find.text('Upload documents'));
      expect(deps.nav.opened, ['verification']);
    });

    testWidgets('pending and rejected (with the reason)', (tester) async {
      await _pumpShell(
          tester,
          CourierTestDeps(
              auth:
                  FakeCourierAuth(kyeStatus: 'pending_super_admin_approval')));
      expect(
          find.text('Your documents are waiting for review.'), findsOneWidget);

      await _pumpShell(
          tester,
          CourierTestDeps(
              auth: FakeCourierAuth(
                  kyeStatus: 'rejected', rejectionReason: 'Blurry photo')));
      expect(find.text('Your documents were not accepted: Blurry photo'),
          findsOneWidget);
      expect(find.text('Upload again'), findsOneWidget);
    });
  });

  group('suspended or paused account', () {
    testWidgets('no job tabs, the reviewer reason is shown', (tester) async {
      final deps = CourierTestDeps(
          auth: FakeCourierAuth(
              accountStatus: 'suspended', suspensionReason: 'Fraud report'));
      await _pumpShell(tester, deps);
      expect(find.byKey(const Key('courier_blocked')), findsOneWidget);
      expect(find.byKey(const Key('courier_shell_nav')), findsNothing);
      expect(find.text('Fraud report'), findsOneWidget);
      expect(
          find.text('Your account was suspended, so no orders will reach you.'),
          findsOneWidget);
    });

    testWidgets('paused by the company: no reason, explained', (tester) async {
      final deps =
          CourierTestDeps(auth: FakeCourierAuth(accountStatus: 'suspended'));
      await _pumpShell(tester, deps);
      expect(find.byKey(const Key('courier_blocked_reason')), findsNothing);
      expect(find.textContaining('Your account is paused'), findsOneWidget);
    });

    testWidgets('check again, support and sign out', (tester) async {
      final deps =
          CourierTestDeps(auth: FakeCourierAuth(accountStatus: 'suspended'));
      await _pumpShell(tester, deps);
      await tester.tap(find.byKey(const Key('courier_blocked_support')));
      await tester.tap(find.byKey(const Key('courier_blocked_sign_out')));
      expect(deps.nav.opened, ['support', 'sign_out']);

      deps.auth.nextUser = UserProfile(
          id: 'emp-1',
          email: 'karim@example.com',
          username: 'Karim',
          role: 'employee',
          kyeStatus: 'approved',
          accountStatus: 'active');
      await tester.tap(find.byKey(const Key('courier_blocked_check')));
      await tester.pumpAndSettle();
      expect(deps.auth.profileCalls, 1);
      expect(find.byKey(const Key('courier_shell')), findsOneWidget);
    });
  });
}
