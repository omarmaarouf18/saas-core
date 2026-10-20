import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/chat/chat_page.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

void main() {
  final active = orderJob(
    status: 'active',
    employeeId: 'emp-1',
    agreed: 45,
    createdAt: DateTime(2026, 10, 19, 14, 5),
  );

  testWidgets('hydrates and subscribes to job:<id>; disconnects on close',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, active);
    expect(find.byKey(const Key('ord_view_active')), findsOneWidget);
    expect(find.byKey(const Key('ord_track_map')), findsOneWidget);
    expect(deps.map.hydrateCalls, ['a1b2c3d4e5f6']);
    expect(deps.map.subscribeCalls, ['job:a1b2c3d4e5f6']);

    await unmountOrder(tester, deps);
    expect(deps.map.disconnects, 1);
  });

  testWidgets('courier, steps, route, price to pay, complaint', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.services = [service(name: 'Nile Express')];
    await pumpOrder(tester, deps, active,
        lookup: FakeCourierLookup({'emp-1': 'Karim'}));

    expect(find.text('The courier is working on your order'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Nile Express'), findsOneWidget);

    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect([
      for (final s in steps) s.label
    ], [
      'You ordered',
      'Karim accepted the order',
      'On the way',
      'Delivered',
    ]);
    expect([
      for (final s in steps) s.state
    ], [
      QdTimelineState.done,
      QdTimelineState.done,
      QdTimelineState.current,
      QdTimelineState.upcoming,
    ]);
    expect(steps[0].time, contains('Today'));
    expect(steps[2].time, 'Now');
    expect(steps[3].time, isNull, reason: 'no per-status times in the API');

    await tester.scrollUntilVisible(find.byKey(const Key('ord_complaint')), 100,
        scrollable: find.descendant(
            of: find.byKey(const Key('ord_list')),
            matching: find.byType(Scrollable)));
    expect(find.text("You'll pay cash"), findsOneWidget);
    expect(find.text('EGP 45'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ord_complaint')));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<CreateTicketDialog>(find.byType(CreateTicketDialog));
    expect(dialog.contextId, 'a1b2c3d4e5f6');
    await unmountOrder(tester, deps);
  });

  testWidgets('assigned: accepted is current, no time on it', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(
        tester, deps, orderJob(status: 'assigned', employeeId: 'emp-1'));
    final steps =
        tester.widget<QdTimeline>(find.byKey(const Key('ord_timeline'))).steps;
    expect(steps[1].label, 'The courier accepted the order');
    expect(steps[1].state, QdTimelineState.current);
    expect(steps[2].state, QdTimelineState.upcoming);
    await unmountOrder(tester, deps);
  });

  testWidgets('chat button opens the job chat', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, active);
    await tester.tap(find.byKey(const Key('ord_chat')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<CustomerChatPage>(find.byType(CustomerChatPage)).channel,
        'job:a1b2c3d4e5f6');
    await unmountOrder(tester, deps);
  });

  group('map notices', () {
    testWidgets('waiting for the courier until a position arrives',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, active);
      expect(find.byKey(const Key('ord_map_waiting')), findsOneWidget);

      deps.map.setCourier(30.055, 31.23);
      await tester.pump();
      expect(find.byKey(const Key('ord_map_waiting')), findsNothing);
      expect(find.byKey(const Key('ord_map_courier_emp-1')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('reconnecting while the socket is down', (tester) async {
      final deps = CustomerTestDeps();
      deps.map.isConnected = false;
      await pumpOrder(tester, deps, active);
      expect(find.byKey(const Key('ord_map_reconnecting')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('access refused', (tester) async {
      final deps = CustomerTestDeps();
      deps.map
        ..isConnected = false
        ..subscriptionError = 'forbidden';
      await pumpOrder(tester, deps, active);
      expect(find.byKey(const Key('ord_map_denied')), findsOneWidget);
      expect(find.byKey(const Key('ord_map_reconnecting')), findsNothing);
      await unmountOrder(tester, deps);
    });
  });

  testWidgets('pull to refresh refetches the job and the courier position',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, active);
    final fetches = deps.marketplace.statusCalls.length;
    await tester.fling(
        find.byKey(const Key('ord_list')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(deps.marketplace.statusCalls.length, greaterThan(fetches));
    expect(deps.map.hydrateCalls, hasLength(2));
    await unmountOrder(tester, deps);
  });

  testWidgets('a failed refresh keeps the view and shows the banner',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, active);
    deps.marketplace.nextStatus = null;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byKey(const Key('ord_stale_banner')), findsOneWidget);
    expect(find.byKey(const Key('ord_view_active')), findsOneWidget);
    await unmountOrder(tester, deps);
  });
}
