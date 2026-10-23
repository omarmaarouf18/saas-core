import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/order_detail_page.dart';
import 'package:frontend/features/owner/orders_page.dart';
import 'package:frontend/features/owner/owner_rules.dart';
import 'package:frontend/features/owner/today_page.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'owner_harness.dart';

// FE-V2-CONSUME item 4: owner order detail, list and Today with job model
// v2 fields.

DateTime _ago(int minutes) => ownerNow.subtract(Duration(minutes: minutes));

JobStatusHistoryEntry _h(String status, int minutesAgo, [String? sub]) =>
    JobStatusHistoryEntry(status: status, at: _ago(minutesAgo), subStatus: sub);

Job v2Job({
  String id = 'a1b2c3d4e5f6',
  String status = 'active',
  String? sub = 'picked_up',
  List<JobStatusHistoryEntry>? history,
  DateTime? createdAt,
}) =>
    ownerJob(
      id: id,
      status: status,
      subStatus: sub,
      createdAt: createdAt ?? _ago(40),
      history: history ??
          [
            _h('pending_dispatch', 40),
            _h('active', 38, 'heading_to_pickup'),
            if (sub == 'picked_up' || status == 'completed')
              _h('active', 10, 'picked_up'),
            if (status == 'completed') _h('completed', 2),
          ],
      etaMinutes: 25,
      recipient: const JobRecipient(
          name: 'Mahmoud', phone: '+201012345678', notes: 'Ring twice'),
      package: const JobPackageDetails(size: 'large', notes: 'Glass'),
      courierPhone: '+201098765432',
      pickupAddress: '15 Kasr El Nil St',
      dropAddress: '4 Tahrir St, Dokki',
    );

List<String> _copied(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

OwnerTestDeps _deps(List<Job> jobs) {
  final deps = OwnerTestDeps();
  deps.owner.nextJobs = jobs;
  deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
  return deps;
}

Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 100,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  group('order detail', () {
    testWidgets('phase chip, address text, recipient, package, ETA',
        (tester) async {
      usePhone(tester);
      final deps = _deps([v2Job()]);
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      expect(find.byKey(const Key('own_order_phase')), findsOneWidget);
      expect(find.text('Picked up'), findsOneWidget);
      expect(find.text('15 Kasr El Nil St · Beside the kiosk'), findsOneWidget);
      expect(find.text('4 Tahrir St, Dokki · Zamalek, 26th of July St'),
          findsOneWidget);
      expect(find.text('Recipient'), findsOneWidget);
      expect(find.text('Mahmoud · \u2066+201012345678\u2069'), findsOneWidget);
      expect(find.text('Ring twice'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Glass'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('own_order_eta')));
      // Picked up 10 min ago + 25 min = 15:45.
      expect(find.text('Arrives around 3:45 PM'), findsOneWidget);
    });

    testWidgets('timeline with owner wording and real times', (tester) async {
      usePhone(tester);
      final deps = _deps([v2Job(status: 'completed', sub: null)]);
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      await _reveal(tester, find.byKey(const Key('own_order_timeline')));
      final steps = tester
          .widget<QdTimeline>(find.byKey(const Key('own_order_timeline')))
          .steps;
      expect([
        for (final s in steps) s.label
      ], [
        'Customer ordered',
        'Karim accepted',
        'The courier picked up the order',
        'Delivered',
      ]);
      expect(steps.last.time, 'Today · 3:28 PM');
      expect(find.byKey(const Key('own_order_delivered')), findsOneWidget);
      // Completed: the server stops sharing phones; no ETA.
      expect(find.byKey(const Key('own_order_eta')), findsNothing);
    });

    testWidgets('call recipient and courier: dial, copy fallback',
        (tester) async {
      usePhone(tester);
      final copied = _copied(tester);
      final deps = _deps([v2Job()]);
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      await tester.tap(find.byKey(const Key('own_call_recipient')));
      await tester.pumpAndSettle();
      expect(deps.launcher.tried.last, Uri.parse('tel:+201012345678'));
      expect(copied, ['+201012345678']);
      expect(
          find.text(
              "Couldn't open the phone app. Number copied: +201012345678."),
          findsOneWidget);
      deps.launcher.opens = (_) => true;
      await _reveal(tester, find.byKey(const Key('own_call_courier')));
      await tester.tap(find.byKey(const Key('own_call_courier')));
      await tester.pumpAndSettle();
      expect(deps.launcher.tried.last, Uri.parse('tel:+201098765432'));
      expect(copied, hasLength(1));
    });

    testWidgets('legacy job: no timeline, no v2 rows, status chip',
        (tester) async {
      usePhone(tester);
      final deps = _deps([ownerJob()]);
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      expect(find.byKey(const Key('own_order_timeline')), findsNothing);
      expect(find.byKey(const Key('own_order_recipient')), findsNothing);
      expect(find.byKey(const Key('own_order_package')), findsNothing);
      expect(find.byKey(const Key('own_order_phase')), findsNothing);
      expect(find.byKey(const Key('own_call_courier')), findsNothing);
      expect(find.text('On the way'), findsOneWidget);
    });

    testWidgets('ride service: passenger wording, no package', (tester) async {
      usePhone(tester);
      final deps = _deps([v2Job(sub: 'heading_to_pickup')]);
      deps.owner.services = [
        {'id': 'svc-1', 'category': 'transport'}
      ];
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      expect(find.text('Going to passenger'), findsOneWidget);
      expect(find.text('Passenger'), findsOneWidget);
      expect(find.byKey(const Key('own_order_package')), findsNothing);
    });
  });

  testWidgets('orders list: phase chip instead of "On the way"',
      (tester) async {
    usePhone(tester);
    final deps = _deps([
      v2Job(id: 'b1', sub: 'heading_to_pickup'),
      ownerJob(id: 'c1'),
    ]);
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));
    expect(
        find.descendant(
            of: find.byKey(const Key('own_order_b1')),
            matching: find.text('Going to pickup')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('own_order_c1')),
            matching: find.text('On the way')),
        findsOneWidget);
  });

  group('Today: delivered today', () {
    OwnerJobExtras none(String _) => OwnerJobExtras.fromJson(null);

    test('by delivery time when the history has it', () {
      final yesterdayOrder = v2Job(
          id: 'y',
          status: 'completed',
          sub: null,
          createdAt: ownerNow.subtract(const Duration(days: 1)),
          history: [
            JobStatusHistoryEntry(
                status: 'pending_dispatch',
                at: ownerNow.subtract(const Duration(days: 1))),
            _h('completed', 30),
          ]);
      final s = todaySummary([yesterdayOrder], none, ownerNow);
      expect(s.ordersToday, 0);
      expect(s.deliveredToday, 1);
      expect(s.deliveredBasis, DeliveredDayBasis.deliveryTime);
    });

    test('placed today, delivered yesterday is not counted', () {
      // Clock skew guard: the delivery day wins over the order day.
      final j = v2Job(id: 'z', status: 'completed', sub: null, history: [
        _h('pending_dispatch', 60),
        JobStatusHistoryEntry(
            status: 'completed',
            at: ownerNow.subtract(const Duration(days: 1))),
      ]);
      expect(todaySummary([j], none, ownerNow).deliveredToday, 0);
    });

    test('legacy: created-day fallback', () {
      final legacy = ownerJob(id: 'l', status: 'completed');
      final s = todaySummary([legacy], none, ownerNow);
      expect(s.deliveredToday, 1);
      expect(s.deliveredBasis, DeliveredDayBasis.orderDay);
    });

    test('mixed', () {
      final s = todaySummary([
        ownerJob(id: 'l', status: 'completed'),
        v2Job(id: 'n', status: 'completed', sub: null),
      ], none, ownerNow);
      expect(s.deliveredToday, 2);
      expect(s.deliveredBasis, DeliveredDayBasis.mixed);
    });

    for (final (jobs, note) in [
      (
        [v2Job(status: 'completed', sub: null)],
        'Delivered and cash count the orders delivered today.'
      ),
      (
        [ownerJob(status: 'completed')],
        'Delivered and cash count the orders placed today.'
      ),
      (
        [
          ownerJob(id: 'l', status: 'completed'),
          v2Job(id: 'n', status: 'completed', sub: null)
        ],
        'Delivered and cash count the orders delivered today. Older orders '
            'without a delivery time count on the day they were placed.'
      ),
    ]) {
      testWidgets('Today page says which: $note', (tester) async {
        usePhone(tester);
        final deps = _deps(jobs);
        await pumpOwner(
            tester,
            deps,
            Scaffold(
                body: OwnerTodayPage(onShowTeam: () {}, onShowOrders: () {})));
        expect(
            tester.widget<Text>(find.byKey(const Key('own_today_note'))).data,
            note);
      });
    }
  });
}
