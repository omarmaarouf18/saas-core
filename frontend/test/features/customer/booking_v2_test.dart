import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/models/marketplace_service.dart';

import 'customer_harness.dart';

// FE-V2-CONSUME item 2: recipient, package and address text on A-Book.

const _pickup = PickedPlace(
    latitude: 30.05, longitude: 31.24, note: 'Floor 3', isDeviceLocation: true);

Future<void> _pump(WidgetTester tester, CustomerTestDeps deps,
    {MarketplaceService? svc}) async {
  usePhone(tester);
  deps.marketplace.nextBookedJob = job(id: 'new-job-1');
  await tester.pumpWidget(customerApp(
      deps, CustomerBookingPage(service: svc ?? service(), pickup: _pickup)));
  await tester.pumpAndSettle();
}

Future<void> _dropoff(WidgetTester tester, {String? address}) async {
  await tester.tap(find.text('Choose the drop-off place'));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(FlutterMap), const Offset(-150, 120));
  await tester.pumpAndSettle();
  if (address != null) {
    await tester.enterText(
        find.byKey(const Key('cust_picker_address')), address);
  }
  await tester.tap(find.byKey(const Key('cust_picker_confirm')));
  await tester.pumpAndSettle();
}

/// Scrolls the booking list until [f] is built and visible.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await _reveal(tester, f);
  await tester.enterText(
      find.descendant(of: f, matching: find.byType(TextField)), text);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await _reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('cust_book_submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default: I am the recipient, no package, old request',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    expect(find.text('Who receives it?'), findsOneWidget);
    expect(find.byKey(const Key('cust_book_recipient_name')), findsNothing);
    await _dropoff(tester);
    await _submit(tester);
    final a = deps.marketplace.bookCalls.single.args;
    for (final k in [
      'pickupAddress',
      'destinationAddress',
      'recipientName',
      'recipientPhone',
      'recipientNotes',
      'packageSize',
      'packageNotes',
    ]) {
      expect(a[k], isNull, reason: k);
    }
    expect(deps.nav.openedOrders.single.$1.id, 'new-job-1');
  });

  testWidgets('someone else + package + address text are sent', (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    await _dropoff(tester, address: '4 Tahrir St, Dokki');
    // The drop-off shows its address text.
    expect(find.text('4 Tahrir St, Dokki'), findsOneWidget);
    await _tapVisible(tester, find.text('Someone else'));
    await _type(tester, 'cust_book_recipient_name', 'Mahmoud');
    await _type(tester, 'cust_book_recipient_phone', '010 1234 5678');
    await _type(tester, 'cust_book_recipient_notes', 'Call first');
    await _tapVisible(tester, find.text('Medium'));
    await _type(tester, 'cust_book_package_notes', 'Fragile');
    await _submit(tester);
    final a = deps.marketplace.bookCalls.single.args;
    expect(a['destinationAddress'], '4 Tahrir St, Dokki');
    expect(a['pickupAddress'], isNull);
    expect(a['recipientName'], 'Mahmoud');
    expect(a['recipientPhone'], '01012345678');
    expect(a['recipientNotes'], 'Call first');
    expect(a['packageSize'], 'medium');
    expect(a['packageNotes'], 'Fragile');
  });

  testWidgets('back to "I am the recipient" sends no recipient',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    await _dropoff(tester);
    await _tapVisible(tester, find.text('Someone else'));
    await _type(tester, 'cust_book_recipient_name', 'Mahmoud');
    await _tapVisible(tester, find.text("I'm the recipient"));
    await _submit(tester);
    expect(deps.marketplace.bookCalls.single.args['recipientName'], isNull);
  });

  testWidgets('invalid phone: field error, nothing sent; typing clears it',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    await _dropoff(tester);
    await _tapVisible(tester, find.text('Someone else'));
    await _type(tester, 'cust_book_recipient_phone', '0123');
    await _submit(tester);
    expect(deps.marketplace.bookCalls, isEmpty);
    expect(
        find.textContaining('Enter an Egyptian mobile number'), findsOneWidget);
    expect(find.text('Check the highlighted fields.'), findsOneWidget);
    await _type(tester, 'cust_book_recipient_phone', '01012345678');
    expect(
        find.textContaining('Enter an Egyptian mobile number'), findsNothing);
    expect(find.text('Check the highlighted fields.'), findsNothing);
    await _submit(tester);
    expect(deps.marketplace.bookCalls, hasLength(1));
  });

  testWidgets('server 400 code shows on its field', (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    deps.marketplace.nextBookError =
        ApiClientException('package_notes_too_long', statusCode: 400);
    await _dropoff(tester);
    await _type(tester, 'cust_book_package_notes', 'Fragile');
    await _submit(tester);
    expect(deps.marketplace.bookCalls, hasLength(1));
    expect(find.text('Use at most 200 characters.'), findsOneWidget);
    expect(find.text('Check the highlighted fields.'), findsOneWidget);
    // Still bookable after fixing it.
    deps.marketplace.nextBookError = null;
    await _type(tester, 'cust_book_package_notes', 'Glass');
    await _submit(tester);
    expect(deps.marketplace.bookCalls, hasLength(2));
  });

  testWidgets('server address code shows under the route', (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    deps.marketplace.nextBookError =
        ApiClientException('address_note_too_long', statusCode: 400);
    await _dropoff(tester);
    await _submit(tester);
    expect(find.byKey(const Key('cust_book_route_error')), findsOneWidget);
    // Choosing the place again clears it.
    await tester.tap(find.text('Your current location'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_book_route_error')), findsNothing);
  });

  testWidgets('rides: passenger wording, no package section', (tester) async {
    await _pump(tester, CustomerTestDeps(),
        svc: service(category: 'transport'));
    expect(find.text("Who's riding?"), findsOneWidget);
    expect(find.text("I'm riding"), findsOneWidget);
    expect(find.text('Package'), findsNothing);
    expect(find.byKey(const Key('cust_book_package_size')), findsNothing);
  });

  testWidgets('Arabic labels', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(customerApp(CustomerTestDeps(),
        CustomerBookingPage(service: service(), pickup: _pickup),
        locale: ar));
    await tester.pumpAndSettle();
    expect(find.text('مين هيستلم؟'), findsOneWidget);
    expect(find.text('أنا المستلم'), findsOneWidget);
  });

  testWidgets('picker: address prefilled on reopen, absent for the search area',
      (tester) async {
    usePhone(tester);
    await tester.pumpWidget(customerApp(
        CustomerTestDeps(),
        const CustomerPickerPage(
            title: 'Drop-off place',
            initial: PickedPlace(
                latitude: 30, longitude: 31, address: '4 Tahrir St'))));
    await tester.pumpAndSettle();
    expect(find.text('4 Tahrir St'), findsOneWidget);

    await tester.pumpWidget(customerApp(
        CustomerTestDeps(),
        const CustomerPickerPage(
            title: 'Search area',
            showNote: false,
            initial: PickedPlace(latitude: 30, longitude: 31))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_picker_address')), findsNothing);
  });
}
