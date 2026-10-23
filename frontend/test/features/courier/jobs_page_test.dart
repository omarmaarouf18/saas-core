import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/jobs_page.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'courier_harness.dart';

String _money(num v) => QdMoney.format(courierEn(), v);

JobStatusHistoryEntry _at(String status, DateTime t) =>
    JobStatusHistoryEntry(status: status, at: t);

Future<CourierTestDeps> _pump(WidgetTester tester, List<Job> jobs,
    {CourierTestDeps? deps}) async {
  usePhone(tester);
  final d = deps ?? CourierTestDeps();
  d.jobs.seed(jobs);
  await pumpCourier(tester, d, const CourierJobsPage());
  await tester.pumpAndSettle();
  return d;
}

Switch _switch(WidgetTester tester) =>
    tester.widget<Switch>(find.byKey(const Key('courier_availability_switch')));

void main() {
  testWidgets('availability switch toggles when no job is active',
      (tester) async {
    final deps = await _pump(tester, []);
    expect(find.text('Available for tasks'), findsOneWidget);
    expect(find.text('We send your location to your company every minute.'),
        findsOneWidget);
    expect(_switch(tester).onChanged, isNotNull);
    await tester.tap(find.byKey(const Key('courier_availability_switch')));
    await tester.pumpAndSettle();
    expect(deps.location.calls.last.name, 'setOnline');
    expect(deps.location.calls.last.args['online'], isFalse);
    expect(find.text('Not available'), findsOneWidget);
  });

  testWidgets('availability is locked during an active job', (tester) async {
    await _pump(tester, [courierJob(subStatus: 'picked_up')]);
    expect(_switch(tester).onChanged, isNull);
    expect(find.text('Locked while a task is in progress.'), findsOneWidget);
  });

  testWidgets('permission denied: banner with settings', (tester) async {
    final deps = CourierTestDeps();
    deps.location.status = LocationSharingStatus.permissionDenied;
    await _pump(tester, [], deps: deps);
    expect(find.byKey(const Key('courier_permission_banner')), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('today: completed count and cash from the timeline',
      (tester) async {
    await _pump(tester, [
      courierJob(id: 'd1', status: 'completed', agreed: 40, history: [
        _at('completed', courierNow.subtract(const Duration(hours: 1)))
      ]),
      courierJob(id: 'd2', status: 'completed', price: 30, history: [
        _at('completed', courierNow.subtract(const Duration(hours: 2)))
      ]),
      courierJob(
          id: 'c1',
          status: 'cancelled',
          cancelReason: 'price_proposal_expired',
          history: [
            _at('cancelled', courierNow.subtract(const Duration(minutes: 5)))
          ]),
    ]);
    expect(
        find.descendant(
            of: find.byKey(const Key('courier_today_count')),
            matching: find.text('2')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('courier_today_cash')),
            matching: find.text(_money(70))),
        findsOneWidget);
    expect(find.textContaining('count by the day they were created'),
        findsNothing);

    // Newest end first; reasons and chips.
    final rows = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('courier_finished_'));
    expect(
        tester
            .widgetList(rows)
            .map((w) => (w.key as ValueKey<String>).value)
            .toList(),
        ['courier_finished_c1', 'courier_finished_d1', 'courier_finished_d2']);
    expect(find.textContaining('The price offer ran out of time.'),
        findsOneWidget);
    expect(find.text('To Zamalek, 26th of July St'), findsNWidgets(3));
  });

  testWidgets('older jobs: counted by creation day, and the page says so',
      (tester) async {
    await _pump(tester, [
      courierJob(
          id: 'old',
          status: 'completed',
          createdAt: courierNow.subtract(const Duration(hours: 2))),
    ]);
    expect(find.textContaining('count by the day they were created'),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('courier_today_count')),
            matching: find.text('1')),
        findsOneWidget);
  });

  testWidgets('nothing finished yet', (tester) async {
    await _pump(tester, [courierJob(subStatus: 'picked_up')]);
    expect(find.byKey(const Key('courier_jobs_empty')), findsOneWidget);
  });

  testWidgets('load error with nothing to show: retry', (tester) async {
    usePhone(tester);
    final deps = CourierTestDeps();
    deps.jobs.nextFetchError = 'offline';
    await pumpCourier(tester, deps, const CourierJobsPage());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('courier_jobs_error')), findsOneWidget);
    deps.jobs.nextFetchError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('courier_jobs_empty')), findsOneWidget);
  });
}
