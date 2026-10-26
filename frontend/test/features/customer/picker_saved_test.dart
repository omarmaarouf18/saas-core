import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/models/saved_address.dart';

import 'customer_harness.dart';

const _home = SavedAddress(
  id: 'addr-home',
  label: 'Home',
  address: '10 Tahrir Square, Cairo',
  addressNote: 'Floor 3, Apt 12',
  latitude: 30.0444,
  longitude: 31.2357,
);

Future<List<PickedPlace?>> _openPicker(
    WidgetTester tester, CustomerTestDeps deps,
    {bool showNote = true}) async {
  usePhone(tester);
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
                showNote: showNote,
                initial: const PickedPlace(latitude: 30.1, longitude: 31.3))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

CustomerTestDeps _deps() {
  final deps = CustomerTestDeps();
  deps.auth.user = deps.auth.user!.copyWith(
    savedAddresses: const [_home],
    frequentAddresses: [_home.address, 'Gym, Nasr City'],
  );
  return deps;
}

void main() {
  testWidgets(
      'a saved place fills the pin, the address and the note in one tap',
      (tester) async {
    final deps = _deps();
    final results = await _openPicker(tester, deps);
    expect(find.text('Saved places'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cust_picker_saved_0')));
    await tester.pumpAndSettle();
    expect(find.text('10 Tahrir Square, Cairo'), findsOneWidget);
    expect(find.text('Floor 3, Apt 12'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    final p = results.single!;
    expect((p.latitude, p.longitude), (30.0444, 31.2357));
    expect(p.address, '10 Tahrir Square, Cairo');
    expect(p.note, 'Floor 3, Apt 12');
  });

  testWidgets('an old string address fills the text only and asks for a pin',
      (tester) async {
    final deps = _deps();
    final results = await _openPicker(tester, deps);
    await tester.tap(find.byKey(const Key('cust_picker_legacy_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_picker_needs_pin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    final p = results.single!;
    // The coordinates are where the map was, not invented.
    expect((p.latitude, p.longitude), (30.1, 31.3));
    expect(p.address, 'Gym, Nasr City');
  });

  testWidgets('no saved places, or the search-area picker: no list',
      (tester) async {
    await _openPicker(tester, CustomerTestDeps());
    expect(find.text('Saved places'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _openPicker(tester, _deps(), showNote: false);
    expect(find.text('Saved places'), findsNothing);
  });
}
