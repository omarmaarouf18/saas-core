import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';

import 'customer_harness.dart';

/// Pumps a launcher that opens the picker and keeps its result.
Future<List<PickedPlace?>> _openPicker(
  WidgetTester tester,
  CustomerTestDeps deps, {
  PickedPlace? initial,
  Locale locale = en,
}) async {
  final results = <PickedPlace?>[];
  await tester.pumpWidget(customerApp(
    deps,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(await CustomerPickerPage.open(
                context,
                title: 'Drop-off place',
                initial: initial)),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    locale: locale,
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('with a place: no locating, confirm returns it with the note',
      (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps();
    final results = await _openPicker(tester, deps,
        initial: const PickedPlace(latitude: 30.1, longitude: 31.3));
    expect(deps.locator.calls, 0);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const Key('cust_picker_pin')), findsOneWidget);
    expect(find.text('Drop-off place'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('cust_picker_note')), 'Gate 3, by the bakery');
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single, isNotNull);
    expect(results.single!.latitude, closeTo(30.1, 1e-9));
    expect(results.single!.longitude, closeTo(31.3, 1e-9));
    expect(results.single!.note, 'Gate 3, by the bakery');
    expect(results.single!.isDeviceLocation, isFalse);
  });

  testWidgets('without a place: uses the device location', (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps(
        locator: FakeLocator(const LocateResult.found(29.9, 31.1)));
    final results = await _openPicker(tester, deps);
    expect(deps.locator.calls, 1);
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single!.latitude, closeTo(29.9, 1e-9));
    expect(results.single!.isDeviceLocation, isTrue);
  });

  testWidgets('dragging the map moves the picked point', (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps();
    final results = await _openPicker(tester, deps,
        initial: const PickedPlace(latitude: 30.1, longitude: 31.3));
    await tester.drag(find.byType(FlutterMap), const Offset(-120, 80));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    final p = results.single!;
    expect(p.latitude == 30.1 && p.longitude == 31.3, isFalse);
  });

  testWidgets('location denied: banner, pick by hand, retry asks again',
      (tester) async {
    usePhone(tester);
    final deps =
        CustomerTestDeps(locator: FakeLocator(const LocateResult.denied()));
    final results = await _openPicker(tester, deps);
    expect(find.byKey(const Key('cust_picker_denied')), findsOneWidget);
    expect(find.textContaining('Location is off'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(deps.locator.calls, 2);

    // Still pickable by hand: confirm returns the default area.
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single!.latitude, closeTo(kDefaultLatitude, 1e-9));
    expect(results.single!.isDeviceLocation, isFalse);
  });

  testWidgets('note is capped at 500 characters', (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps();
    await _openPicker(tester, deps,
        initial: const PickedPlace(latitude: 30, longitude: 31));
    await tester.enterText(
        find.byKey(const Key('cust_picker_note')), 'x' * 600);
    await tester.pump();
    final field = tester.widget<TextField>(find.descendant(
        of: find.byKey(const Key('cust_picker_note')),
        matching: find.byType(TextField)));
    expect(field.controller!.text.length, kAddressNoteMaxLength);
  });

  testWidgets('back returns null', (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps();
    final results = await _openPicker(tester, deps,
        initial: const PickedPlace(latitude: 30, longitude: 31));
    await tester.tap(find.byKey(const Key('cust_picker_back')));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [$locale]', (tester) async {
      usePhone(tester);
      await _openPicker(tester, CustomerTestDeps(),
          initial: const PickedPlace(latitude: 30, longitude: 31),
          locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
