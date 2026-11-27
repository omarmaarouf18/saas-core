import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/maps/app_map.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/saved_address.dart';

import 'customer_harness.dart';

// FE-V2-CONSUME item 2 + ADDR-REQUIRED: recipient, package and typed
// address with structured details (app 2.1.0) on A-Book.

const _pickup = PickedPlace(
    latitude: 30.05,
    longitude: 31.24,
    address: '15 Kasr El Nil St',
    note: 'Floor 3',
    isDeviceLocation: true);

Future<void> _pump(WidgetTester tester, CustomerTestDeps deps,
    {MarketplaceService? svc, PickedPlace? pickup}) async {
  usePhone(tester);
  deps.marketplace.nextBookedJob = job(id: 'new-job-1');
  await tester.pumpWidget(customerApp(
      deps,
      CustomerBookingPage(
          service: svc ?? service(), pickup: pickup ?? _pickup)));
  await tester.pumpAndSettle();
}

Future<void> _dropoff(WidgetTester tester,
    {String address = '4 Tahrir St, Dokki',
    String? building,
    String? floor,
    String? apartment}) async {
  await tester.tap(find.text('Choose the drop-off place'));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(AppMap), const Offset(-150, 120));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('cust_picker_address')), address);
  if (building != null) {
    await tester.enterText(
        find.byKey(const Key('cust_picker_building')), building);
  }
  if (floor != null) {
    await tester.enterText(find.byKey(const Key('cust_picker_floor')), floor);
  }
  if (apartment != null) {
    await tester.enterText(
        find.byKey(const Key('cust_picker_apartment')), apartment);
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
  testWidgets('default: I am the recipient, no package, addresses sent',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    expect(find.text('Who receives it?'), findsOneWidget);
    expect(find.byKey(const Key('cust_book_recipient_name')), findsNothing);
    await _dropoff(tester);
    await _submit(tester);
    final a = deps.marketplace.bookCalls.single.args;
    expect(a['pickupAddress'], '15 Kasr El Nil St');
    expect(a['destinationAddress'], '4 Tahrir St, Dokki');
    for (final k in [
      'pickupBuilding',
      'pickupFloor',
      'pickupApartment',
      'destinationBuilding',
      'destinationFloor',
      'destinationApartment',
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
    expect(a['pickupAddress'], '15 Kasr El Nil St');
    expect(a['destinationAddress'], '4 Tahrir St, Dokki');
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
    // The toggle is above the field now: scroll back up to it.
    await tester.scrollUntilVisible(find.text("I'm the recipient"), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm the recipient"));
    await tester.pumpAndSettle();
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
    await tester.tap(find.text('15 Kasr El Nil St'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_book_route_error')), findsNothing);
  });

  testWidgets('the booking form blocks an empty or too-short address',
      (tester) async {
    final deps = CustomerTestDeps();
    // Start with pickup missing an address
    const noAddrPickup =
        PickedPlace(latitude: 30.05, longitude: 31.24, note: 'Gate 2');
    await _pump(tester, deps, pickup: noAddrPickup);
    await _dropoff(tester, address: '4 Tahrir St, Dokki');

    // Submit with empty pickup address: blocked
    await _submit(tester);
    expect(deps.marketplace.bookCalls, isEmpty);
    expect(find.byKey(const Key('cust_book_route_error')), findsOneWidget);
    expect(find.text('Write the address of this stop.'), findsOneWidget);
    expect(find.text('Check the highlighted fields.'), findsOneWidget);

    // Edit pickup to a too-short address (4 characters)
    await tester.tap(find.text('Gate 2'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cust_picker_address')), 'four');
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();

    await _submit(tester);
    expect(deps.marketplace.bookCalls, isEmpty);
    expect(find.byKey(const Key('cust_book_route_error')), findsOneWidget);
    expect(find.text('An address is too short. Use at least 5 characters.'),
        findsOneWidget);

    // Edit pickup to valid address (>= 5 chars): submit passes
    await tester.tap(find.text('four'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('cust_picker_address')), '15 Kasr El Nil St');
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();

    await _submit(tester);
    expect(deps.marketplace.bookCalls, hasLength(1));
  });

  testWidgets('the optional fields are sent only when filled', (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    await _dropoff(
      tester,
      address: '4 Tahrir St, Dokki',
      building: 'Building 12',
      floor: 'Floor 3',
      apartment: 'Apt 7',
    );
    await _submit(tester);
    final a = deps.marketplace.bookCalls.single.args;
    expect(a['pickupAddress'], '15 Kasr El Nil St');
    expect(a['pickupBuilding'], isNull);
    expect(a['pickupFloor'], isNull);
    expect(a['pickupApartment'], isNull);
    expect(a['destinationAddress'], '4 Tahrir St, Dokki');
    expect(a['destinationBuilding'], 'Building 12');
    expect(a['destinationFloor'], 'Floor 3');
    expect(a['destinationApartment'], 'Apt 7');
  });

  testWidgets('a saved address pre-fills all fields in picker', (tester) async {
    final deps = CustomerTestDeps();
    const saved = SavedAddress(
      id: 'addr-work',
      label: 'Work',
      address: '20 Smart Village, Giza',
      building: 'Building B1',
      floor: 'Floor 2',
      apartment: 'Suite 204',
      addressNote: 'Near entrance A',
      latitude: 30.08,
      longitude: 31.02,
    );
    deps.auth.user = deps.auth.user!.copyWith(savedAddresses: [saved]);
    await _pump(tester, deps);

    // Open drop-off picker
    await tester.tap(find.text('Choose the drop-off place'));
    await tester.pumpAndSettle();
    expect(find.text('Saved places'), findsOneWidget);

    // Tap saved address chip
    await tester.tap(find.byKey(const Key('cust_picker_saved_0')));
    await tester.pumpAndSettle();

    // Verify all fields are pre-filled
    expect(find.text('20 Smart Village, Giza'), findsOneWidget);
    expect(find.text('Building B1'), findsOneWidget);
    expect(find.text('Floor 2'), findsOneWidget);
    expect(find.text('Suite 204'), findsOneWidget);
    expect(find.text('Near entrance A'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();

    await _submit(tester);
    final a = deps.marketplace.bookCalls.single.args;
    expect(a['destinationAddress'], '20 Smart Village, Giza');
    expect(a['destinationBuilding'], 'Building B1');
    expect(a['destinationFloor'], 'Floor 2');
    expect(a['destinationApartment'], 'Suite 204');
    expect(a['destinationAddressNote'], 'Near entrance A');
  });

  testWidgets('rides: passenger wording, no package section', (tester) async {
    await _pump(tester, CustomerTestDeps(),
        svc: service(category: 'transport'));
    expect(find.text("Who's riding?"), findsOneWidget);
    expect(find.text("I'm riding"), findsOneWidget);
    expect(find.text('Package'), findsNothing);
    expect(find.byKey(const Key('cust_book_package_size')), findsNothing);
  });

  testWidgets('Arabic labels and RTL test', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(customerApp(CustomerTestDeps(),
        CustomerBookingPage(service: service(), pickup: _pickup),
        locale: ar));
    await tester.pumpAndSettle();
    expect(find.text('مين هيستلم؟'), findsOneWidget);
    expect(find.text('أنا المستلم'), findsOneWidget);

    // Open picker in Arabic
    await tester.tap(find.text('اختار مكان التسليم'));
    await tester.pumpAndSettle();
    expect(find.text('العنوان'), findsOneWidget);
    expect(find.text('العمارة · اختياري'), findsOneWidget);
    expect(find.text('الدور · اختياري'), findsOneWidget);
    expect(find.text('الشقة · اختياري'), findsOneWidget);
    expect(find.text('علامة تساعد المندوب · اختياري'), findsOneWidget);
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
