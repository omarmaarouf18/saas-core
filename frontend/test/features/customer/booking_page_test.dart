import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/price_estimate.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'customer_harness.dart';

const _pickup = PickedPlace(
    latitude: 30.05, longitude: 31.24, note: 'Floor 3', isDeviceLocation: true);

Future<void> _pumpBooking(WidgetTester tester, CustomerTestDeps deps,
    {MarketplaceService? svc, Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(customerApp(
    deps,
    CustomerBookingPage(service: svc ?? service(), pickup: _pickup),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

QdButton _submit(WidgetTester tester) =>
    tester.widget<QdButton>(find.byKey(const Key('cust_book_submit')));

/// Opens the drop-off picker, moves the map, confirms.
Future<void> _chooseDropoff(WidgetTester tester, {String? note}) async {
  await tester.tap(find.text('Choose the drop-off place'));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(FlutterMap), const Offset(-150, 120));
  await tester.pumpAndSettle();
  if (note != null) {
    await tester.enterText(find.byKey(const Key('cust_picker_note')), note);
  }
  await tester.tap(find.byKey(const Key('cust_picker_confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('before a drop-off: disabled button, base price, COD only',
      (tester) async {
    await _pumpBooking(tester, CustomerTestDeps());
    expect(find.text('Confirm order'), findsOneWidget);
    expect(find.text('Nile Express'), findsOneWidget);
    expect(find.text('Your current location'), findsOneWidget);
    expect(find.text('Floor 3'), findsOneWidget);
    expect(find.text('Choose the drop-off place first'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
    // Tenant base price wins over the service base price.
    expect(find.text('EGP 25'), findsOneWidget);
    expect(find.text('EGP 5'), findsOneWidget);
    expect(find.text('Choose the drop-off place to see the estimate.'),
        findsOneWidget);
    expect(find.text('Cash to the courier'), findsOneWidget);
    expect(find.text('Electronic payment is coming soon'), findsOneWidget);
    // No coordinates anywhere.
    expect(find.textContaining('30.05'), findsNothing);
  });

  testWidgets('after a drop-off: estimate breakdown and enabled button',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pumpBooking(tester, deps);
    await _chooseDropoff(tester, note: 'Tower B');
    expect(find.text('Tower B'), findsOneWidget);
    expect(find.text('Order now'), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);
    expect(find.text('Estimate'), findsOneWidget);
    expect(find.textContaining('About EGP'), findsOneWidget);
    expect(find.textContaining('straight-line distance'), findsOneWidget);
  });

  testWidgets('submit books COD once and opens the order, replacing the stack',
      (tester) async {
    final deps = CustomerTestDeps();
    final booked = job(id: 'new-job-1', status: 'pending_dispatch');
    deps.marketplace.nextBookedJob = booked;
    deps.marketplace.bookGate = Completer<void>();
    await _pumpBooking(tester, deps);
    await _chooseDropoff(tester, note: 'Tower B');

    await tester.tap(find.byKey(const Key('cust_book_submit')));
    await tester.pump();
    // Double-submit guard: a second tap while the request runs is ignored.
    await tester.tap(find.byKey(const Key('cust_book_submit')));
    await tester.pump();
    expect(deps.marketplace.bookCalls, hasLength(1));
    expect(_submit(tester).loading, isTrue);

    deps.marketplace.bookGate!.complete();
    await tester.pumpAndSettle();

    final args = deps.marketplace.bookCalls.single.args;
    expect(args['paymentMethod'], 'cod');
    expect(args['serviceId'], 'svc-1');
    expect(args['userId'], 'customer-jwt');
    expect(args['latitude'], 30.05);
    expect(args['longitude'], 31.24);
    expect(args['pickupAddressNote'], 'Floor 3');
    expect(args['destinationAddressNote'], 'Tower B');
    expect(deps.nav.openedOrders.single.$1.id, 'new-job-1');
    expect(deps.nav.openedOrders.single.$2, isTrue);
    expect(deps.marketplace.jobCalls, 1);
    // The same trip cannot be booked again from this page.
    expect(_submit(tester).onPressed, isNull);
  });

  testWidgets('estimate matches the pure formula', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextBookedJob = job();
    await _pumpBooking(tester, deps);
    await _chooseDropoff(tester);
    await tester.tap(find.byKey(const Key('cust_book_submit')));
    await tester.pumpAndSettle();
    final a = deps.marketplace.bookCalls.single.args;
    final e = estimateTripPrice(
      service: service(),
      fromLat: a['latitude'] as double,
      fromLon: a['longitude'] as double,
      toLat: a['destinationLatitude'] as double,
      toLon: a['destinationLongitude'] as double,
    );
    expect(e.total, greaterThan(25));
    expect(find.text('About ${QdMoney.format(lookupEn(), e.total)}'),
        findsOneWidget);
  });

  testWidgets('booking error shows a banner and allows a retry',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextBookError = apiError('Service unavailable');
    await _pumpBooking(tester, deps);
    await _chooseDropoff(tester);
    await tester.tap(find.byKey(const Key('cust_book_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_book_error')), findsOneWidget);
    expect(
        find.textContaining("We couldn't place your order."), findsOneWidget);
    expect(deps.nav.openedOrders, isEmpty);
    expect(_submit(tester).onPressed, isNotNull);
    expect(_submit(tester).loading, isFalse);
  });

  testWidgets('a null booking response is an error, not a navigation',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pumpBooking(tester, deps);
    await _chooseDropoff(tester);
    await tester.tap(find.byKey(const Key('cust_book_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_book_error')), findsOneWidget);
    expect(deps.nav.openedOrders, isEmpty);
  });

  testWidgets('a closed company cannot be booked', (tester) async {
    final deps = CustomerTestDeps();
    await _pumpBooking(tester, deps, svc: service(open: false));
    await _chooseDropoff(tester);
    expect(find.textContaining('closed now'), findsOneWidget);
    expect(_submit(tester).onPressed, isNull);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [$locale]', (tester) async {
      await _pumpBooking(tester, CustomerTestDeps(), locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
