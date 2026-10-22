import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/order_detail_page.dart';

import 'owner_harness.dart';

void main() {
  OwnerTestDeps depsWith(List<dynamic> jobs,
      {Map<String, Map<String, dynamic>> json = const {}}) {
    final deps = OwnerTestDeps();
    deps.owner.nextJobs = [for (final j in jobs) j];
    deps.owner.nextJobJson = json;
    deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
    return deps;
  }

  final requested = ownerJob(
    requestStatus: 'pending',
    requestReason: 'My bike broke down',
    requestedAt: ownerNow.subtract(const Duration(minutes: 12)),
  );

  testWidgets('details: route, courier, cash payment, created time',
      (tester) async {
    usePhone(tester);
    final deps = depsWith([ownerJob()]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));

    expect(find.textContaining('#QD-A1B2C3D4'), findsOneWidget);
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Beside the kiosk'), findsOneWidget);
    expect(find.text('Zamalek, 26th of July St'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Cash · EGP 42'), findsOneWidget);
    expect(find.text('Today · 2:30 PM'), findsOneWidget);
    expect(find.byKey(const Key('own_cancel_request')), findsNothing);
    expect(find.byKey(const Key('own_distance_review')), findsNothing);
    // No ETA / recipient / history rows (JOB-V2-BE).
    expect(find.textContaining('ETA'), findsNothing);
    // The owner DTO has no customer name: "Customer #<short id>".
    expect(find.text('Customer \u2066#cust-9\u2069'), findsOneWidget);
  });

  testWidgets('"see on the map" opens the old fleet map', (tester) async {
    usePhone(tester);
    final deps = depsWith([ownerJob()]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    await tester.tap(find.byKey(const Key('own_order_map')));
    expect(deps.nav.opened, ['fleet_map']);
  });

  testWidgets('distance review note and recorded cash when present',
      (tester) async {
    usePhone(tester);
    final deps = depsWith([
      ownerJob(status: 'completed'),
    ], json: {
      'a1b2c3d4e5f6': {
        'actual_cash_amount': 40,
        'distance_review': {'actual_km': 1.2, 'booked_km': 6},
      },
    });
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    expect(find.text('Distance looked short, review'), findsOneWidget);
    expect(find.textContaining('1.2 km of the 6 km booked'), findsOneWidget);
    expect(find.text('Cash recorded'), findsOneWidget);
    expect(find.text('EGP 40'), findsOneWidget);
    // Completed: the owner can no longer cancel.
    expect(find.byKey(const Key('own_order_cancel')), findsNothing);
  });

  testWidgets('cancellation request: approve after confirm', (tester) async {
    usePhone(tester);
    final deps = depsWith([requested]);
    deps.owner.jobsAfterRespond = [copyJob(requested, status: 'cancelled')];
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));

    expect(find.text('Karim wants to cancel this order'), findsOneWidget);
    expect(find.text('“My bike broke down”'), findsOneWidget);
    expect(find.text('Asked 12 min ago'), findsOneWidget);

    await tester.tap(find.byKey(const Key('own_cancel_request_approve')));
    await tester.pumpAndSettle();
    expect(find.text('Approve the cancellation?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pumpAndSettle();

    expect(deps.owner.respondCalls, [
      {'jobId': 'a1b2c3d4e5f6', 'decision': 'accept'}
    ]);
    expect(find.text('Cancellation approved. The order is cancelled.'),
        findsOneWidget);
    expect(find.byKey(const Key('own_cancel_request')), findsNothing);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('cancellation request: "not now" sends nothing', (tester) async {
    usePhone(tester);
    final deps = depsWith([requested]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    await tester.tap(find.byKey(const Key('own_cancel_request_keep')));
    await tester.pumpAndSettle();
    expect(find.text('Karim stays on the order and has to finish it.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('own_confirm_no')));
    await tester.pumpAndSettle();
    expect(deps.owner.respondCalls, isEmpty);
  });

  testWidgets('409 race on the response: explained and refreshed',
      (tester) async {
    usePhone(tester);
    final deps = depsWith([requested]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    deps.owner.nextRespondError =
        apiErr(409, 'cancellation request has expired');
    // Meanwhile the server already resolved it.
    deps.owner.nextJobs = [copyJob(requested, requestStatus: 'expired')];
    final callsBefore = deps.owner.jobCalls;

    await tester.tap(find.byKey(const Key('own_cancel_request_keep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pumpAndSettle();

    expect(deps.owner.respondCalls.single['decision'], 'decline');
    expect(
        find.text('This request already changed, it may have run out. '
            'The order was refreshed.'),
        findsOneWidget);
    expect(deps.owner.jobCalls, callsBefore + 1);
    expect(find.byKey(const Key('own_cancel_request')), findsNothing);
  });

  testWidgets('other response error: notice with retry', (tester) async {
    usePhone(tester);
    final deps = depsWith([requested]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    deps.owner.nextRespondError = apiErr(503);
    await tester.tap(find.byKey(const Key('own_cancel_request_keep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    expect(find.byKey(const Key('own_cancel_request')), findsOneWidget);
  });

  for (final (status, can) in [
    ('pending', true),
    ('active', true),
    ('pending_dispatch', false),
    ('awaiting_price_response', false),
    ('completed', false),
    ('cancelled', false),
  ]) {
    testWidgets('owner cancel button for $status: $can', (tester) async {
      usePhone(tester);
      final deps = depsWith([ownerJob(status: status)]);
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
      expect(find.byKey(const Key('own_order_cancel')),
          can ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('owner cancel: reason required, COD wording, cancelled',
      (tester) async {
    usePhone(tester);
    final deps = depsWith([ownerJob()]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    await tester.tap(find.byKey(const Key('own_order_cancel')));
    await tester.pumpAndSettle();
    expect(
        find.text('The customer and the courier will be told. '
            "Write why you're cancelling."),
        findsOneWidget);
    // Disabled until a reason is typed.
    await tester.tap(find.byKey(const Key('own_cancel_confirm')));
    await tester.pumpAndSettle();
    expect(deps.owner.cancelCalls, isEmpty);

    await tester.enterText(
        find.byKey(const Key('own_cancel_reason')), '  Customer asked  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('own_cancel_confirm')));
    await tester.pumpAndSettle();
    expect(deps.owner.cancelCalls, [
      {'jobId': 'a1b2c3d4e5f6', 'reason': 'Customer asked'}
    ]);
    expect(find.text('Order cancelled.'), findsOneWidget);
    expect(find.text('Customer asked'), findsOneWidget); // reason row
    expect(find.byKey(const Key('own_order_cancel')), findsNothing);
  });

  testWidgets('owner cancel: non-COD mentions the held amount; error stays',
      (tester) async {
    usePhone(tester);
    final deps =
        depsWith([ownerJob(status: 'pending', payment: 'wallet', held: 55)]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'a1b2c3d4e5f6'));
    await tester.tap(find.byKey(const Key('own_order_cancel')));
    await tester.pumpAndSettle();
    expect(find.textContaining('EGP 55 held for this order'), findsOneWidget);

    deps.owner.nextCancelError = apiErr(500);
    await tester.enterText(find.byKey(const Key('own_cancel_reason')), 'x');
    await tester.pump();
    await tester.tap(find.byKey(const Key('own_cancel_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_cancel_error')), findsOneWidget);
    expect(find.byKey(const Key('own_cancel_sheet')), findsOneWidget);
  });

  testWidgets('unassigned order and unknown courier', (tester) async {
    usePhone(tester);
    final deps = depsWith([
      ownerJob(id: 'job-unassigned', status: 'pending', employeeId: null),
      ownerJob(id: 'job-gone', employeeId: 'emp-zzzzzz9'),
    ]);
    await pumpOwner(
        tester, deps, const OwnerOrderDetailPage(jobId: 'job-unassigned'));
    expect(find.text('Not assigned yet'), findsOneWidget);
    await tester.pumpWidget(
        ownerApp(deps, const OwnerOrderDetailPage(jobId: 'job-gone')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Courier'), findsWidgets);
    expect(find.textContaining('emp-zz'), findsOneWidget);
  });

  testWidgets('a job that left the list: empty state with refresh',
      (tester) async {
    usePhone(tester);
    final deps = depsWith([]);
    await pumpOwner(tester, deps, const OwnerOrderDetailPage(jobId: 'nope'));
    expect(find.byKey(const Key('own_order_missing')), findsOneWidget);
    final calls = deps.owner.jobCalls;
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(deps.owner.jobCalls, calls + 1);
  });
}
