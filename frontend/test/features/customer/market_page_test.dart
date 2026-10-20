import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/market_page.dart';

import 'customer_harness.dart';

const _home = PickedPlace(latitude: 30.07, longitude: 31.28, note: 'Office');

Future<void> _pumpMarket(WidgetTester tester, CustomerTestDeps deps,
    {String? category = 'delivery',
    PickedPlace? pickup = _home,
    Locale locale = en,
    bool settle = true}) async {
  usePhone(tester);
  await tester.pumpWidget(customerApp(
    deps,
    CustomerMarketPage(category: category, pickup: pickup, now: () => fixedNow),
    locale: locale,
  ));
  if (settle) await tester.pumpAndSettle();
}

void main() {
  final open = service(id: 'open', name: 'Nile Express', distanceKm: 2.4);
  final far = service(
      id: 'far', name: 'Delta Couriers', distanceKm: 7.5, finalPrice: 60);
  final closed = service(
    id: 'closed',
    name: 'Night Owl',
    distanceKm: 1.1,
    open: false,
    reopensAt: DateTime(2026, 10, 20, 9),
  );
  final ride = service(id: 'ride', name: 'Cairo Rides', category: 'transport');

  testWidgets('loads near the pickup and lists the category', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [far, closed, ride, open];
    await _pumpMarket(tester, deps);

    expect(deps.locator.calls, 0);
    final call = deps.marketplace.serviceCalls.single;
    expect(call['nearBy'], isTrue);
    expect(call['lat'], 30.07);
    expect(call['lon'], 31.28);
    expect(call['radius'], kDefaultMarketRadiusKm);
    expect(call['sortBy'], 'distance');

    expect(find.text('Deliver an order'), findsOneWidget); // title
    expect(find.text('Near Office · up to 50 km'), findsOneWidget);
    expect(find.text('3 companies available'), findsOneWidget);
    expect(find.text('Cairo Rides'), findsNothing);
    expect(find.text('About EGP 37'), findsOneWidget);
    expect(find.text('2.4 km from you'), findsOneWidget);
    expect(find.text('Open'), findsNWidgets(2));
    expect(find.text('Closed'), findsOneWidget);
    expect(find.textContaining('Opens '), findsOneWidget);
    // No ratings and no "top rated" sort (a rating needs a request per row).
    expect(find.text('Top rated'), findsNothing);

    // Nearest first, closed last.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Nile Express'), lessThan(y('Delta Couriers')));
    expect(y('Delta Couriers'), lessThan(y('Night Owl')));
  });

  testWidgets('closed companies are visible but not bookable', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [closed];
    await _pumpMarket(tester, deps);
    await tester.tap(find.text('Night Owl'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm order'), findsNothing);
  });

  testWidgets('tapping an open company opens the booking page', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [open];
    await _pumpMarket(tester, deps);
    await tester.tap(find.text('Nile Express'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm order'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget); // pickup carried over
  });

  testWidgets('cheapest sort asks the server to sort by price', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [open, far];
    await _pumpMarket(tester, deps);
    await tester.tap(find.text('Cheapest'));
    await tester.pumpAndSettle();
    expect(deps.marketplace.serviceCalls.last['sortBy'], 'price');
  });

  testWidgets('loading, then error with retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.servicesGate = Completer<void>();
    deps.marketplace.nextServicesError = 'Service unavailable';
    await _pumpMarket(tester, deps, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('cust_market_loading')), findsOneWidget);

    deps.marketplace.servicesGate!.complete();
    deps.marketplace.servicesGate = null;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_market_error')), findsOneWidget);

    deps.marketplace.nextServicesError = null;
    deps.marketplace.nextServices = [open];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(deps.marketplace.serviceCalls, hasLength(2));
    expect(find.text('Nile Express'), findsOneWidget);
  });

  testWidgets('empty state offers the filters', (tester) async {
    final deps = CustomerTestDeps();
    await _pumpMarket(tester, deps);
    expect(find.byKey(const Key('cust_market_empty')), findsOneWidget);
    await tester.tap(find.text('Change filters'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_market_filter_sheet')), findsOneWidget);
  });

  testWidgets('filter sheet changes the radius', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [open];
    await _pumpMarket(tester, deps);
    await tester.tap(find.byKey(const Key('cust_market_filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 km'));
    await tester.pump();
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(deps.marketplace.serviceCalls.last['radius'], 10);
    expect(find.text('Near Office · up to 10 km'), findsOneWidget);
  });

  testWidgets('without a pickup: locating state, then device location',
      (tester) async {
    final deps = CustomerTestDeps(
        locator: FakeLocator(const LocateResult.found(29.95, 31.1)));
    deps.locator.gate = Completer<void>();
    deps.marketplace.nextServices = [open];
    await _pumpMarket(tester, deps, pickup: null, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('cust_market_locating')), findsOneWidget);
    expect(find.text('Finding your location…'), findsOneWidget);

    deps.locator.gate!.complete();
    await tester.pumpAndSettle();
    expect(deps.marketplace.serviceCalls.single['lat'], 29.95);
    expect(find.text('Near you · up to 50 km'), findsOneWidget);
  });

  testWidgets('location denied: default area and a pick-area banner',
      (tester) async {
    final deps =
        CustomerTestDeps(locator: FakeLocator(const LocateResult.denied()));
    deps.marketplace.nextServices = [open];
    await _pumpMarket(tester, deps, pickup: null);
    expect(find.byKey(const Key('cust_market_location_off')), findsOneWidget);
    expect(deps.marketplace.serviceCalls.single['lat'], kDefaultLatitude);
    await tester.tap(find.text('Pick area on map'));
    await tester.pumpAndSettle();
    expect(find.text('Search area'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_market_location_off')), findsNothing);
    expect(deps.marketplace.serviceCalls, hasLength(2));
  });

  testWidgets('all services when no category is given', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextServices = [open, ride];
    await _pumpMarket(tester, deps, category: null);
    expect(find.text('All services'), findsOneWidget);
    expect(find.text('Cairo Rides'), findsOneWidget);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [$locale]', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextServices = [open, far, closed];
      await _pumpMarket(tester, deps, locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
