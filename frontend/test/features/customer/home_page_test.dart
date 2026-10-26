import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/customer_shell.dart';

import 'customer_harness.dart';

Future<void> _pumpShell(WidgetTester tester, CustomerTestDeps deps,
    {Locale locale = en, bool settle = true}) async {
  usePhone(tester);
  await tester.pumpWidget(
      customerApp(deps, CustomerShell(now: () => fixedNow), locale: locale));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('header, three services, and the newest ongoing order',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.notifications.unreadCount = 2;
    deps.marketplace.services = [service(id: 'svc-1', category: 'delivery')];
    deps.marketplace.nextJobs = [
      job(id: 'old11111', status: 'active', createdAt: DateTime(2026, 10, 1)),
      job(
          id: 'new22222',
          status: 'awaiting_price_response',
          createdAt: DateTime(2026, 10, 19, 14)),
      job(
          id: 'done3333',
          status: 'completed',
          createdAt: DateTime(2026, 10, 19, 15)),
    ];
    await _pumpShell(tester, deps);

    expect(find.text('Pick up from'), findsOneWidget);
    expect(find.text('Your current location'), findsOneWidget);
    expect(find.text('What are you sending today?'), findsOneWidget);
    expect(find.text('Deliver an order'), findsOneWidget);
    expect(find.text('Ship a parcel'), findsOneWidget);
    expect(find.text('Ride'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // unread badge

    // awaiting_price_response counts as ongoing (old Home missed it).
    final card = find.byKey(const Key('cust_home_ongoing'));
    expect(card, findsOneWidget);
    expect(find.text('Deliver an order · \u2066#QD-NEW22222\u2069'),
        findsOneWidget);
    expect(find.text('New price offered'), findsOneWidget);
    expect(find.text('To Zamalek, 26th of July St'), findsOneWidget);

    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(deps.nav.openedOrders.single.$1.id, 'new22222');
    expect(deps.nav.openedOrders.single.$2, isFalse);
    expect(deps.marketplace.jobCalls, 2); // refreshed on return
  });

  testWidgets('loading state while orders load', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.jobsGate = Completer<void>();
    await _pumpShell(tester, deps, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('cust_home_ongoing_loading')), findsOneWidget);
    deps.marketplace.jobsGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_home_no_ongoing')), findsOneWidget);
  });

  testWidgets('error state with retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobsError = 'Service unavailable';
    await _pumpShell(tester, deps);
    expect(find.byKey(const Key('cust_home_ongoing_error')), findsOneWidget);
    deps.marketplace.nextJobsError = null;
    deps.marketplace.nextJobs = [job(status: 'pending')];
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_home_ongoing')), findsOneWidget);
  });

  testWidgets('no ongoing order', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextJobs = [
      job(status: 'completed'),
      job(id: 'x2', status: 'cancelled'),
      job(id: 'x3', status: 'unavailable'),
    ];
    await _pumpShell(tester, deps);
    expect(find.text('No ongoing orders right now.'), findsOneWidget);
  });

  testWidgets('location denied: pickup asks to choose a location',
      (tester) async {
    final deps =
        CustomerTestDeps(locator: FakeLocator(const LocateResult.denied()));
    await _pumpShell(tester, deps);
    expect(find.text('Choose a location'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cust_home_pickup')));
    await tester.pumpAndSettle();
    expect(find.text('Pickup place'), findsOneWidget);
  });

  testWidgets('a service opens the marketplace pre-filtered near the pickup',
      (tester) async {
    final deps = CustomerTestDeps(
        locator: FakeLocator(const LocateResult.found(30.01, 31.02)));
    await _pumpShell(tester, deps);
    await tester.tap(find.byKey(const Key('cust_home_cat_transport')));
    await tester.pumpAndSettle();
    expect(find.text('Ride'), findsWidgets); // marketplace title
    final call = deps.marketplace.serviceCalls.single;
    expect(call['lat'], 30.01);
    expect(call['lon'], 31.02);
  });

  testWidgets('double tap on a service pushes one page', (tester) async {
    final deps = CustomerTestDeps();
    await _pumpShell(tester, deps);
    await tester.tap(find.byKey(const Key('cust_home_cat_delivery')));
    await tester.tap(find.byKey(const Key('cust_home_cat_delivery')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(deps.marketplace.serviceCalls, hasLength(1));
  });

  testWidgets('bell opens notifications', (tester) async {
    final deps = CustomerTestDeps();
    await _pumpShell(tester, deps);
    await tester.tap(find.byKey(const Key('cust_home_bell')));
    await tester.pumpAndSettle();
    expect(deps.nav.notificationsOpened, 1);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [$locale]', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextJobs = [job(status: 'active')];
      await _pumpShell(tester, deps, locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
