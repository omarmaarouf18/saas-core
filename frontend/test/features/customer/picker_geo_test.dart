import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/geo/geo_models.dart';
import 'package:frontend/core/geo/geo_service.dart';
import 'package:frontend/core/maps/app_map.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';

import '../../helpers/fake_geo_service.dart';
import 'customer_harness.dart';

Future<List<PickedPlace?>> _openPickerWithGeo(
  WidgetTester tester,
  FakeGeoService geo, {
  PickedPlace? initial = const PickedPlace(latitude: 30.1, longitude: 31.3),
  bool showNote = true,
  bool reverseAddress = false,
  Locale locale = en,
}) async {
  usePhone(tester);
  final results = <PickedPlace?>[];
  await tester.pumpWidget(
    GeoScope(
      service: geo,
      child: customerApp(
        CustomerTestDeps(),
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    results.add(await CustomerPickerPage.open(
                  context,
                  title: 'Drop-off place',
                  initial: initial,
                  showNote: showNote,
                  reverseAddress: reverseAddress,
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets(
      'pin move calls /geo/reverse once per stop, shows loading hint, and fills address',
      (tester) async {
    final gate = Completer<void>();
    final geo = FakeGeoService(
      nextReverse: const GeoReverseResult(
        address: '12 Brazil St, Zamalek',
        area: 'Zamalek',
      ),
    )..reverseGate = gate;

    final results = await _openPickerWithGeo(tester, geo);
    expect(geo.reverseCalls, isEmpty);

    await tester.drag(find.byType(AppMap), const Offset(-100, 60));
    await tester.pump();

    expect(geo.reverseCalls, hasLength(1));
    expect(find.byKey(const Key('cust_picker_reversing')), findsOneWidget);
    expect(find.text('Finding address...'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cust_picker_reversing')), findsNothing);
    expect(find.text('12 Brazil St, Zamalek'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single!.address, '12 Brazil St, Zamalek');
  });

  testWidgets('never overwrites text the user typed after the last pin move',
      (tester) async {
    final gate = Completer<void>();
    final geo = FakeGeoService(
      nextReverse: const GeoReverseResult(
        address: 'Old Reversed Address',
        area: 'Downtown',
      ),
    )..reverseGate = gate;

    final results = await _openPickerWithGeo(tester, geo);

    // Move pin -> starts /geo/reverse in flight.
    await tester.drag(find.byType(AppMap), const Offset(-90, 50));
    await tester.pump();
    expect(geo.reverseCalls, hasLength(1));

    // User types manually while reverse geocode is still in flight.
    await tester.enterText(
      find.byKey(const Key('cust_picker_address')),
      'My typed street 42',
    );
    await tester.pump();

    // Reverse completes; it must NOT overwrite user's typed address.
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('My typed street 42'), findsOneWidget);
    expect(find.text('Old Reversed Address'), findsNothing);

    // A new pin move after typing DOES fill the new reversed address.
    geo.reverseGate = null;
    geo.nextReverse = const GeoReverseResult(
      address: 'New Pin Address 99',
      area: 'Maadi',
    );
    await tester.drag(find.byType(AppMap), const Offset(-60, 40));
    await tester.pumpAndSettle();

    expect(geo.reverseCalls, hasLength(2));
    expect(find.text('New Pin Address 99'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single!.address, 'New Pin Address 99');
  });

  testWidgets(
      'reverseAddress mode (saved-address pin picker) fills returned address on pin move',
      (tester) async {
    final geo = FakeGeoService(
      nextReverse: const GeoReverseResult(
        address: '10 Gezira St, Zamalek',
        area: 'Zamalek',
      ),
    );
    final results = await _openPickerWithGeo(
      tester,
      geo,
      showNote: false,
      reverseAddress: true,
    );

    await tester.drag(find.byType(AppMap), const Offset(-80, 40));
    await tester.pumpAndSettle();

    expect(geo.reverseCalls, hasLength(1));
    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();
    expect(results.single!.address, '10 Gezira St, Zamalek');
  });
}
