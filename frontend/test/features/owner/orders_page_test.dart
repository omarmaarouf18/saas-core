import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/orders_page.dart';

import 'owner_harness.dart';

void main() {
  List<dynamic> mixed() => [
        ownerJob(id: 'on-req-0001', requestStatus: 'pending'),
        ownerJob(
            id: 'on-offer-002',
            status: 'pending_dispatch',
            employeeId: null,
            offeredTo: 'emp-2'),
        ownerJob(
            id: 'on-price-003',
            status: 'awaiting_price_response',
            proposed: 55,
            price: 42),
        ownerJob(id: 'done-00004', status: 'completed', employeeId: 'emp-2'),
        ownerJob(id: 'cxl-000005', status: 'cancelled'),
        ownerJob(id: 'unav-00006', status: 'unavailable', employeeId: null),
      ];

  OwnerTestDeps deps0() {
    final deps = OwnerTestDeps();
    deps.owner.nextJobs = [for (final j in mixed()) j];
    deps.owner.nextEmployees = [
      staff('emp-1', 'Karim'),
      staff('emp-2', 'Sara')
    ];
    return deps;
  }

  Finder row(String id) => find.byKey(Key('own_order_$id'));

  testWidgets('tabs split ongoing / done / cancelled with an ongoing count',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));

    expect(find.text('Ongoing · 3'), findsOneWidget);
    expect(row('on-req-0001'), findsOneWidget);
    expect(row('on-offer-002'), findsOneWidget);
    expect(row('on-price-003'), findsOneWidget);
    expect(row('done-00004'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(row('done-00004'), findsOneWidget);
    expect(row('on-req-0001'), findsNothing);

    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    expect(row('cxl-000005'), findsOneWidget);
    expect(row('unav-00006'), findsOneWidget);
  });

  testWidgets('row summaries: request chip, offer, price proposal, courier',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));

    expect(find.text('Cancellation requested'), findsOneWidget);
    // The reference is LTR-isolated; the courier name follows it.
    expect(find.textContaining(RegExp(r'#QD-ON-REQ-0.* · Karim$')),
        findsOneWidget);
    expect(find.text('Offered to Sara'), findsOneWidget);
    expect(find.text('Price offer: EGP 55 instead of EGP 42'), findsOneWidget);
    expect(find.text('To Zamalek, 26th of July St'), findsOneWidget);
  });

  testWidgets('search by id (with #QD-) and by courier name', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));

    await tester.enterText(
        find.byKey(const Key('own_orders_search')), '#qd-on-price');
    await tester.pump();
    expect(row('on-price-003'), findsOneWidget);
    expect(row('on-req-0001'), findsNothing);

    await tester.enterText(find.byKey(const Key('own_orders_search')), 'sar');
    await tester.pump();
    expect(row('on-offer-002'), findsNothing); // only offered, not assigned
    expect(find.byKey(const Key('own_orders_no_match')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(row('done-00004'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('own_orders_search')), 'zzz');
    await tester.pump();
    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();
    expect(row('done-00004'), findsOneWidget);
  });

  testWidgets('tap opens the order detail', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));
    await tester.tap(row('on-req-0001'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_order_page')), findsOneWidget);
    expect(find.byKey(const Key('own_cancel_request')), findsOneWidget);
  });

  testWidgets('pull to refresh reloads jobs and employees', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));
    final jobs = deps.owner.jobCalls, staffCalls = deps.owner.employeeCalls;
    await tester.fling(
        find.byKey(const Key('own_orders_list')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(deps.owner.jobCalls, jobs + 1);
    expect(deps.owner.employeeCalls, staffCalls + 1);
  });

  testWidgets('loading, then empty per tab', (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    deps.owner.jobsGate = Completer<void>();
    final refresh = deps.data.refresh();
    await tester
        .pumpWidget(ownerApp(deps, const Scaffold(body: OwnerOrdersPage())));
    await tester.pump();
    expect(find.byKey(const Key('own_orders_loading')), findsOneWidget);
    deps.owner.jobsGate!.complete();
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('No ongoing orders'), findsOneWidget);
    await tester.tap(find.text('Cancelled'));
    await tester.pumpAndSettle();
    expect(find.text('No cancelled orders'), findsOneWidget);
  });

  testWidgets('error with retry; stale banner when a refresh fails',
      (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    deps.owner.nextJobsError = 'down';
    await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));
    expect(find.byKey(const Key('own_orders_error')), findsOneWidget);

    deps.owner.nextJobsError = null;
    deps.owner.nextJobs = [ownerJob()];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(row('a1b2c3d4e5f6'), findsOneWidget);

    deps.owner.nextJobsError = 'down';
    await deps.data.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_orders_stale')), findsOneWidget);
    expect(row('a1b2c3d4e5f6'), findsOneWidget);
  });

  testWidgets('standalone: back button and prefilled search', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps,
        const OwnerOrdersPage(initialQuery: 'Karim', standalone: true));
    expect(find.text('Orders'), findsOneWidget); // app bar title
    expect(row('on-req-0001'), findsOneWidget);
    expect(row('on-price-003'), findsOneWidget);
    expect(row('on-offer-002'), findsNothing);
  });
}
