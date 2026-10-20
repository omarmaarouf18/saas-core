import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_shell.dart';

import 'customer_harness.dart';

Future<void> _pumpOrders(WidgetTester tester, CustomerTestDeps deps,
    {Locale locale = en, bool settle = true}) async {
  usePhone(tester);
  await tester.pumpWidget(customerApp(
      deps, CustomerShell(initialIndex: 1, now: () => fixedNow),
      locale: locale, wrapTheme: false));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  final jobs = [
    job(
        id: 'act11111',
        status: 'active',
        createdAt: DateTime(2026, 10, 19, 14, 5)),
    job(id: 'neg22222', status: 'awaiting_price_response'),
    job(id: 'dis33333', status: 'pending_dispatch'),
    job(
        id: 'don44444',
        status: 'completed',
        createdAt: DateTime(2026, 10, 12, 9)),
    job(id: 'can55555', status: 'cancelled', price: 30),
    job(id: 'una66666', status: 'unavailable'),
  ];

  testWidgets('ongoing tab uses job_rules and shows route, price, chips',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = jobs;
    deps.marketplace.services = [service(id: 'svc-1', category: 'shipping')];
    await _pumpOrders(tester, deps);

    expect(find.text('My orders'), findsWidgets);
    expect(find.text('Ongoing · 3'), findsOneWidget);
    expect(find.byKey(const Key('cust_order_act11111')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_neg22222')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_dis33333')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_don44444')), findsNothing);
    expect(find.text('Ship a parcel'), findsNWidgets(3));
    expect(find.text('Today · 2:05 PM'), findsOneWidget);
    expect(find.text('Beside the kiosk'), findsNWidgets(3));
    expect(find.text('Cash on delivery'), findsNWidgets(3));
    expect(find.text('EGP 42'), findsNWidgets(3));
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('New price offered'), findsOneWidget);
    expect(find.text('Finding a courier'), findsOneWidget);
  });

  testWidgets('past tab: finished jobs, cancelled price struck through',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = jobs;
    await _pumpOrders(tester, deps);
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_order_don44444')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_can55555')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_una66666')), findsOneWidget);
    expect(find.byKey(const Key('cust_order_act11111')), findsNothing);
    expect(find.textContaining('Oct 12'), findsOneWidget);
    final cancelled = tester.widget<Text>(find.text('EGP 30'));
    expect(cancelled.style?.decoration, TextDecoration.lineThrough);
    expect(find.text('Order'), findsNWidgets(3)); // service not loaded
  });

  testWidgets('tapping an order opens its detail', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = jobs;
    await _pumpOrders(tester, deps);
    await tester.tap(find.byKey(const Key('cust_order_neg22222')));
    await tester.pumpAndSettle();
    expect(deps.nav.openedOrders.single.$1.id, 'neg22222');
  });

  testWidgets('empty ongoing tab offers browsing services', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = [job(status: 'completed')];
    await _pumpOrders(tester, deps);
    expect(find.text('No ongoing orders'), findsOneWidget);
    await tester.tap(find.text('Browse services'));
    await tester.pumpAndSettle();
    expect(find.text('All services'), findsOneWidget);
  });

  testWidgets('empty past tab', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = [job(status: 'active')];
    await _pumpOrders(tester, deps);
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('No past orders yet'), findsOneWidget);
  });

  testWidgets('loading, error and retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.jobsGate = Completer<void>();
    deps.marketplace.nextJobsError = 'Service unavailable';
    await _pumpOrders(tester, deps, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('cust_orders_loading')), findsOneWidget);
    deps.marketplace.jobsGate!.complete();
    deps.marketplace.jobsGate = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_orders_error')), findsOneWidget);
    deps.marketplace.nextJobsError = null;
    deps.marketplace.nextJobs = jobs;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Ongoing · 3'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads orders', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = jobs;
    await _pumpOrders(tester, deps);
    final before = deps.marketplace.jobCalls;
    await tester.fling(
        find.byKey(const Key('cust_orders_list')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(deps.marketplace.jobCalls, before + 1);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [$locale]', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextJobs = jobs;
      await _pumpOrders(tester, deps, locale: locale);
      await tester.tap(find.byKey(const Key('cust_orders_tabs')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
