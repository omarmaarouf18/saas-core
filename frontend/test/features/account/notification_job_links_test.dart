import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/features/courier/courier_shell.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/features/owner/owner_shell.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/services/notification_tap_router.dart';
import 'package:frontend/ui/components/qd_bottom_nav.dart';

import '../courier/courier_harness.dart' as cour;
import '../customer/customer_harness.dart' as cust;
import '../owner/owner_harness.dart' as own;

NotificationModel n(String type, {String? jobId, String body = ''}) =>
    NotificationModel(
      id: 'n1',
      type: type,
      tenantId: 't',
      jobId: jobId,
      title: '',
      body: body,
      timestamp: DateTime(2026, 10, 19),
    );

/// Push source for tests: a cold-start tap and captured listeners.
class FakeTapSource implements PushTapSource {
  NotificationModel? initial;
  void Function(NotificationModel)? opened;
  void Function(NotificationModel)? foreground;

  @override
  Future<NotificationModel?> initialTap() async => initial;

  @override
  void listen(
      {required void Function(NotificationModel n) onOpened,
      required void Function(NotificationModel n) onForeground}) {
    opened = onOpened;
    foreground = onForeground;
  }
}

int tab(WidgetTester tester, String navKey) =>
    tester.widget<QdBottomNav>(find.byKey(Key(navKey))).currentIndex;

void main() {
  group('rules', () {
    const job = NotificationTargetKind.job;
    test('job_id + a job event type → the exact job, old link as fallback', () {
      expect(
          notificationTarget(n('job_picked_up', jobId: 'j1'), 'user'),
          const NotificationTarget(
              job, 'j1', NotificationTarget(NotificationTargetKind.orders)));
      expect(
          notificationTarget(n('cancellation_requested', jobId: 'j2'), 'owner'),
          const NotificationTarget(
              job, 'j2', NotificationTarget(NotificationTargetKind.orders)));
      expect(
          notificationTarget(n('job_offer', jobId: 'j3'), 'employee'),
          const NotificationTarget(
              job, 'j3', NotificationTarget(NotificationTargetKind.task)));
      for (final t in kJobEventTypes) {
        expect(notificationTarget(n(t, jobId: 'x'), 'user').kind, job,
            reason: t);
      }
    });

    test('no job_id, unknown type or unknown role: the old behaviour', () {
      expect(notificationTarget(n('job_accepted'), 'user'),
          const NotificationTarget(NotificationTargetKind.orders));
      expect(notificationTarget(n('something_new', jobId: 'j1'), 'user'),
          NotificationTarget.none);
      expect(notificationTarget(n('kyc_rejected', jobId: 'j1'), 'owner'),
          const NotificationTarget(NotificationTargetKind.verification));
      expect(notificationTarget(n('job_accepted', jobId: 'j1'), 'admin'),
          NotificationTarget.none);
    });

    test('job_id from history / SSE JSON and from push data', () {
      expect(
          NotificationModel.fromJson({
            'id': 'a',
            'type': 'job_cancelled',
            'job_id': 'j9',
            'timestamp': '2026-10-19T10:00:00Z',
          }).jobId,
          'j9');
      expect(
          NotificationModel.fromJson({'id': 'a', 'job_id': ''}).jobId, isNull);
      final p = NotificationModel.fromPushData(
          {'id': 'p', 'type': 'job_picked_up', 'tenant_id': 't', 'job_id': 'j'},
          title: 'T');
      expect((p.type, p.jobId, p.title), ('job_picked_up', 'j', 'T'));
    });

    test('follow: openJob when the shell has it, else the fallback', () {
      final calls = <String>[];
      final target = notificationTarget(n('job_accepted', jobId: 'j1'), 'user');
      NotificationLinks(
        openJob: (_, id) => calls.add('job $id'),
        openOrders: (_) => calls.add('orders'),
      ).follow(_FakeContext(), target);
      NotificationLinks(openOrders: (_) => calls.add('orders'))
          .follow(_FakeContext(), target);
      expect(calls, ['job j1', 'orders']);
    });
  });

  group('push taps', () {
    testWidgets('customer: cold-start tap opens that order', (tester) async {
      cust.usePhone(tester);
      final deps = cust.CustomerTestDeps();
      deps.marketplace.nextStatus = cust.job(id: 'job-77');
      final src = FakeTapSource()
        ..initial = NotificationModel.fromPushData(
            {'type': 'job_picked_up', 'job_id': 'job-77'});
      final router = NotificationTapRouter(source: src);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: cust.customerApp(deps, const CustomerShell())));
      await tester.pumpAndSettle();
      expect(deps.marketplace.statusCalls, contains('job-77'));
      expect(deps.nav.openedOrders.single.$1.id, 'job-77');
    });

    testWidgets('customer: not yours / gone → notice and My orders',
        (tester) async {
      cust.usePhone(tester);
      final deps = cust.CustomerTestDeps(); // nextStatus null = 403/404
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: cust.customerApp(deps, const CustomerShell())));
      await tester.pumpAndSettle();
      src.opened!(NotificationModel.fromPushData(
          {'type': 'job_cancelled', 'job_id': 'other-1'}));
      await tester.pumpAndSettle();
      expect(deps.nav.openedOrders, isEmpty);
      expect(find.byKey(const Key('ntf_job_missing')), findsOneWidget);
      expect(tab(tester, 'customer_shell_nav'), 1);
    });

    testWidgets('customer: foreground push shows a notice; View follows it',
        (tester) async {
      cust.usePhone(tester);
      final deps = cust.CustomerTestDeps();
      deps.marketplace.nextStatus = cust.job(id: 'job-5');
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: cust.customerApp(deps, const CustomerShell())));
      await tester.pumpAndSettle();
      src.foreground!(NotificationModel.fromPushData(
          {'type': 'job_picked_up', 'job_id': 'job-5'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ntf_push_foreground')), findsOneWidget);
      expect(find.text('Your order was picked up'), findsOneWidget);
      expect(deps.nav.openedOrders, isEmpty);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(deps.nav.openedOrders.single.$1.id, 'job-5');
    });

    testWidgets('owner: tap opens the order detail; unknown job → notice',
        (tester) async {
      own.usePhone(tester);
      final deps = own.OwnerTestDeps();
      deps.owner.nextEmployees = [own.staff('emp-1', 'Karim')];
      deps.owner.nextJobs = [own.ownerJob(id: 'own-job-1')];
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: own.ownerApp(deps, OwnerShell(now: () => own.ownerNow),
              withData: false)));
      await tester.pumpAndSettle();
      src.opened!(NotificationModel.fromPushData(
          {'type': 'cancellation_requested', 'job_id': 'own-job-1'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_page')), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      src.opened!(NotificationModel.fromPushData(
          {'type': 'dispute_resolved', 'job_id': 'not-mine'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_page')), findsNothing);
      expect(find.byKey(const Key('ntf_job_missing')), findsOneWidget);
      expect(tab(tester, 'owner_shell_nav'), 1);
    });

    for (final (name, jobs, id, want) in [
      (
        'offer → Task',
        [cour.courierJob(id: 'offer-1', status: 'pending_dispatch')],
        'offer-1',
        0
      ),
      (
        'current job → Task',
        [cour.courierJob(id: 'run-1', status: 'active')],
        'run-1',
        0
      ),
      (
        'finished → My jobs',
        [cour.courierJob(id: 'done-1', status: 'completed')],
        'done-1',
        1
      ),
    ]) {
      testWidgets('courier: $name', (tester) async {
        cour.usePhone(tester);
        final deps = cour.CourierTestDeps();
        deps.jobs.seed(jobs);
        final src = FakeTapSource();
        final router = NotificationTapRouter(source: src);
        await router.start();
        await tester.pumpWidget(NotificationTapScope(
            router: router,
            child: cour.courierApp(
                deps, CourierShell(initialIndex: 2, now: () => cour.courierNow),
                withController: false)));
        await tester.pump();
        await tester.pump();
        src.opened!(NotificationModel.fromPushData(
            {'type': 'job_offer', 'job_id': id}));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tab(tester, 'courier_shell_nav'), want);
        expect(find.byKey(const Key('ntf_job_missing')), findsNothing);
      });
    }

    testWidgets('courier: a job that is not theirs → notice, My jobs',
        (tester) async {
      cour.usePhone(tester);
      final deps = cour.CourierTestDeps();
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: cour.courierApp(deps, CourierShell(now: () => cour.courierNow),
              withController: false)));
      await tester.pump();
      src.opened!(NotificationModel.fromPushData(
          {'type': 'cancellation_resolved', 'job_id': 'gone'}));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tab(tester, 'courier_shell_nav'), 1);
      expect(find.byKey(const Key('ntf_job_missing')), findsOneWidget);
    });
  });
}

class _FakeContext extends Fake implements BuildContext {}
