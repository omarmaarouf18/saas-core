import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/geo/geo_models.dart';
import 'package:frontend/core/geo/geo_service.dart';
import 'package:frontend/core/maps/app_map.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/ui/qd_ui.dart';

import '../../helpers/fake_geo_service.dart';
import '../account/account_harness.dart' as acct;
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

  group('Item 4 fallbacks and RTL', () {
    testWidgets(
        'geo_unavailable on reverse and autocomplete falls back to manual typing in picker',
        (tester) async {
      const err = GeoException(
        GeoFailureKind.unavailable,
        statusCode: 503,
        errorCode: 'geo_unavailable',
      );
      final geo = FakeGeoService()
        ..reverseError = err
        ..autocompleteError = err;

      final results = await _openPickerWithGeo(tester, geo);

      // Pin move fails silently and never blocks the form.
      await tester.drag(find.byType(AppMap), const Offset(-80, 40));
      await tester.pumpAndSettle();
      expect(find.byType(QdBanner), findsNothing);

      // Typing triggers autocomplete -> 503 geo_unavailable -> manual fallback.
      await tester.enterText(
        find.byKey(const Key('cust_picker_address')),
        '15 Kasr El Nil, Downtown',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.byType(QdBanner), findsNothing);
      expect(find.byKey(const Key('addr_search_suggestions')), findsNothing);
      expect(
        find.text(
            'Address suggestions unavailable — you can type it manually.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cust_picker_confirm')));
      await tester.pumpAndSettle();
      expect(results.single!.address, '15 Kasr El Nil, Downtown');
    });

    testWidgets(
        'network error and 429 rate limit fall back to manual typing in saved-address editor',
        (tester) async {
      usePhone(tester);
      final geo = FakeGeoService()
        ..autocompleteError = const GeoException(GeoFailureKind.network);

      final deps = acct.AccountTestDeps(
        auth: acct.FakeAuthFlow(
          user:
              acct.FakeAuthFlow.customer(saved: const [], addresses: const []),
        ),
      );
      const pin = _StubPin(PickedPlace(latitude: 30.05, longitude: 31.24));

      await tester.pumpWidget(
        GeoScope(
          service: geo,
          child: acct.accountApp(
            deps,
            SavedAddressesPage(pickPin: pin.call),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('addresses_add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('address_input')),
        '99 El Hegaz St',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byType(QdBanner), findsNothing);
      expect(
        find.text(
            'Address suggestions unavailable — you can type it manually.'),
        findsOneWidget,
      );

      // Also verify 429 rate limit fallback.
      geo.autocompleteError = const GeoException(
        GeoFailureKind.rateLimited,
        statusCode: 429,
        errorCode: 'rate_limited',
      );
      await tester.enterText(
        find.byKey(const Key('address_input')),
        '99 El Hegaz St, Heliopolis',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byType(QdBanner), findsNothing);

      await tester.drag(
        find.byKey(const Key('address_editor_list')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('address_pin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('address_save')));
      await tester.pumpAndSettle();

      final sent = deps.auth.lastProfileUpdate?['saved_addresses'] as List?;
      expect(sent, hasLength(1));
      expect(sent!.first['address'], '99 El Hegaz St, Heliopolis');
    });

    testWidgets(
        'RTL [ar]: Arabic search suggestions, pin loading hint, and fallback render right-to-left without overflow',
        (tester) async {
      final gate = Completer<void>();
      final geo = FakeGeoService(
        nextSuggestions: const [
          GeoSuggestion(
            placeId: 'ChIJ_ar',
            primary: '١٥ شارع قصر النيل',
            secondary: 'وسط البلد، القاهرة',
          ),
        ],
        nextPlace: const GeoPlace(
          lat: 30.0444,
          lng: 31.2357,
          address: '١٥ شارع قصر النيل، عابدين',
          area: 'عابدين',
        ),
        nextReverse: const GeoReverseResult(
          address: '٤ شارع التحرير، الدقي',
          area: 'الدقي',
        ),
      )..reverseGate = gate;

      await _openPickerWithGeo(tester, geo, locale: ar);

      final ctx = tester.element(find.byKey(const Key('cust_picker_address')));
      expect(Directionality.of(ctx), TextDirection.rtl);

      // Reverse loading hint in Arabic
      await tester.drag(find.byType(AppMap), const Offset(-80, 40));
      await tester.pump();
      expect(find.text('بنحدد العنوان...'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('٤ شارع التحرير، الدقي'), findsOneWidget);

      // Search suggestions in Arabic
      await tester.enterText(
        find.byKey(const Key('cust_picker_address')),
        'قصر النيل',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addr_search_suggestions')), findsOneWidget);
      expect(find.text('١٥ شارع قصر النيل'), findsOneWidget);

      await tester.tap(find.byKey(const Key('addr_suggestion_0')));
      await tester.pumpAndSettle();
      expect(find.text('١٥ شارع قصر النيل، عابدين'), findsOneWidget);

      // Arabic fallback string on geo_unavailable
      geo.autocompleteError = const GeoException(
        GeoFailureKind.unavailable,
        statusCode: 503,
        errorCode: 'geo_unavailable',
      );
      await tester.enterText(
        find.byKey(const Key('cust_picker_address')),
        'المعادي',
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'اقتراحات العناوين مش متاحة دلوقتي — تقدر تكتب العنوان يدوي.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _StubPin {
  const _StubPin(this.place);
  final PickedPlace place;
  Future<PickedPlace?> call(BuildContext _, PickedPlace? __) async => place;
}
