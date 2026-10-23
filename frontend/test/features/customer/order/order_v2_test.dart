import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/ui/qd_ui.dart';

import '../customer_harness.dart';
import 'order_harness.dart';
import 'order_v2_fixtures.dart';

// FE-V2-CONSUME item 3: the customer order page with job model v2 fields.

Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 100,
      scrollable: find.descendant(
          of: find.byKey(const Key('ord_list')),
          matching: find.byType(Scrollable)));
  await tester.pump();
}

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

void main() {
  testWidgets('picked up: phase, ETA, history timeline with real times',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2(),
        lookup: FakeCourierLookup({'emp-1': 'Karim'}));
    expect(find.text('On the way to you'), findsOneWidget);
    // Picked up 6 min ago + 12 min = fixedNow + 6 min (15:36).
    expect(find.byKey(const Key('ord_eta')), findsOneWidget);
    expect(find.text('Arrives around 3:36 PM'), findsOneWidget);

    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect([
      for (final s in steps) s.label
    ], [
      'You ordered',
      'Karim accepted the order',
      'The courier picked up the order',
      'Delivered',
    ]);
    expect([
      for (final s in steps) s.state
    ], [
      QdTimelineState.done,
      QdTimelineState.done,
      QdTimelineState.done,
      QdTimelineState.current,
    ]);
    expect(steps[0].time, 'Today · 3:00 PM');
    expect(steps[1].time, 'Today · 3:02 PM');
    expect(steps[2].time, 'Today · 3:24 PM');
    expect(steps[3].time, isNull);
    await unmountOrder(tester, deps);
  });

  testWidgets('heading to pickup: pickup wording and ETA', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps,
        orderJobV2(subStatus: 'heading_to_pickup', etaMinutes: 40));
    expect(find.text('The courier is on the way to pick up your order'),
        findsOneWidget);
    // Accepted 28 min ago + 40 = 15:42.
    expect(find.text('At the pickup around 3:42 PM'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('ride wording when the service is a ride', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.services = [service(category: 'transport')];
    await pumpOrder(tester, deps, orderJobV2());
    expect(find.text('On the way to your destination'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('job_recipient')));
    expect(find.text('Passenger'), findsOneWidget);
    expect(find.byKey(const Key('job_package')), findsNothing);
    await unmountOrder(tester, deps);
  });

  testWidgets('no ETA / no phase: the old lines', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(
        tester, deps, orderJobV2(subStatus: null, etaMinutes: null));
    expect(find.text('The courier is working on your order'), findsOneWidget);
    expect(find.byKey(const Key('ord_eta')), findsNothing);
    await unmountOrder(tester, deps);
  });

  testWidgets('legacy job (no history): created-at-only timeline',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2(history: const []));
    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect(steps[2].label, 'On the way');
    expect(steps[2].time, 'Now');
    // No history entry to anchor the ETA on.
    expect(find.byKey(const Key('ord_eta')), findsNothing);
    await unmountOrder(tester, deps);
  });

  testWidgets('route shows address then note; recipient and package rows',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2());
    await _reveal(tester, find.byKey(const Key('job_package')));
    expect(find.text('15 Kasr El Nil St, Downtown · Floor 3'), findsOneWidget);
    expect(find.text('4 Tahrir St, Dokki · Beside the metro'), findsOneWidget);
    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Mahmoud · \u2066+201012345678\u2069'), findsOneWidget);
    expect(find.text('Call before arriving'), findsOneWidget);
    expect(find.text('Package'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('call the courier: dials; copies when no phone app',
      (tester) async {
    final copied = _copied(tester);
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2());
    await tester.tap(find.byKey(const Key('ord_call')));
    await tester.pump();
    expect(deps.launcher.tried, [Uri.parse('tel:+201098765432')]);
    expect(copied, ['+201098765432']);
    expect(
        find.text("Couldn't open the phone app. Number copied: +201098765432."),
        findsOneWidget);

    deps.launcher.opens = (_) => true;
    await tester.tap(find.byKey(const Key('ord_call')));
    await tester.pump();
    expect(copied, hasLength(1));
    await unmountOrder(tester, deps);
  });

  testWidgets('no courier_phone: no call button', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2(courierPhone: null));
    expect(find.byKey(const Key('ord_call')), findsNothing);
    expect(find.byKey(const Key('ord_chat')), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('completed: full timeline with delivery time', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps,
        orderJobV2(status: 'completed', subStatus: null, courierPhone: null));
    await _reveal(tester, find.byKey(const Key('ord_timeline')));
    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect(steps.every((s) => s.state == QdTimelineState.done), isTrue);
    expect(steps.last.time, 'Today · 3:29 PM');
    await unmountOrder(tester, deps);
  });

  testWidgets('cancelled with history: ends with the cancelled step',
      (tester) async {
    final deps = CustomerTestDeps();
    final job = orderJobV2(status: 'cancelled', subStatus: null, history: [
      JobStatusHistoryEntry(
          status: 'pending_dispatch',
          at: fixedNow.subtract(const Duration(minutes: 10))),
      JobStatusHistoryEntry(
          status: 'cancelled',
          at: fixedNow.subtract(const Duration(minutes: 4))),
    ]);
    await pumpOrder(tester, deps, job);
    await _reveal(tester, find.byKey(const Key('ord_timeline')));
    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect([for (final s in steps) s.label], ['You ordered', 'Cancelled']);
    expect(steps.last.time, 'Today · 3:26 PM');
    await unmountOrder(tester, deps);
  });

  testWidgets('legacy cancelled: no timeline (as before)', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps,
        orderJobV2(status: 'cancelled', subStatus: null, history: const []));
    expect(find.byKey(const Key('ord_timeline')), findsNothing);
    await unmountOrder(tester, deps);
  });

  testWidgets('Arabic', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJobV2(), locale: ar);
    expect(find.text('في الطريق ليك'), findsOneWidget);
    expect(find.textContaining('هيوصل حوالي'), findsOneWidget);
    await unmountOrder(tester, deps);
  });
}
