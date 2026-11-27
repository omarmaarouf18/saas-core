import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/geo/address_search_field.dart';
import 'package:frontend/core/geo/geo_models.dart';
import 'package:frontend/core/geo/geo_service.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/qd_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../features/account/account_harness.dart' as acct;
import '../../features/customer/customer_harness.dart';
import '../../helpers/fake_geo_service.dart';

Widget _wrapField({
  required GeoService geo,
  required TextEditingController controller,
  ValueChanged<GeoPlace>? onPlaceSelected,
  Locale locale = const Locale('en'),
}) {
  return GeoScope(
    service: geo,
    child: MaterialApp(
      theme: qdLightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: AddressSearchField(
            fieldKey: const Key('test_addr_field'),
            label: 'Address',
            controller: controller,
            onPlaceSelected: onPlaceSelected,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('no autocomplete call below 3 runes', (tester) async {
    final geo = FakeGeoService();
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrapField(geo: geo, controller: ctrl));

    await tester.enterText(find.byKey(const Key('test_addr_field')), 'ab');
    await tester.pump(const Duration(milliseconds: 500));
    expect(geo.autocompleteCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('test_addr_field')), '  أب  ');
    await tester.pump(const Duration(milliseconds: 500));
    expect(geo.autocompleteCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('test_addr_field')), 'مصر');
    await tester.pump(const Duration(milliseconds: 450));
    expect(geo.autocompleteCalls, hasLength(1));
    expect(geo.autocompleteCalls.single.query, 'مصر');
  });

  testWidgets('400ms debounce coalesces rapid keystrokes', (tester) async {
    final geo = FakeGeoService();
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_wrapField(geo: geo, controller: ctrl));

    await tester.enterText(find.byKey(const Key('test_addr_field')), 'Tah');
    await tester.pump(const Duration(milliseconds: 200));
    expect(geo.autocompleteCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('test_addr_field')), 'Tahrir');
    await tester.pump(const Duration(milliseconds: 350));
    expect(geo.autocompleteCalls, isEmpty);

    await tester.pump(const Duration(milliseconds: 60));
    expect(geo.autocompleteCalls, hasLength(1));
    expect(geo.autocompleteCalls.single.query, 'Tahrir');
  });

  testWidgets('session token is reused per search and ends with /geo/place',
      (tester) async {
    final geo = FakeGeoService();
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    GeoPlace? selected;

    await tester.pumpWidget(_wrapField(
      geo: geo,
      controller: ctrl,
      onPlaceSelected: (p) => selected = p,
    ));

    await tester.enterText(find.byKey(const Key('test_addr_field')), 'Tah');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byKey(const Key('test_addr_field')), 'Tahrir');
    await tester.pump(const Duration(milliseconds: 450));

    expect(geo.autocompleteCalls, hasLength(2));
    final s1 = geo.autocompleteCalls[0].sessionToken;
    final s2 = geo.autocompleteCalls[1].sessionToken;
    expect(s1, isNotEmpty);
    expect(s2, s1);

    await tester.tap(find.byKey(const Key('addr_suggestion_0')));
    await tester.pumpAndSettle();

    expect(geo.placeCalls, hasLength(1));
    expect(geo.placeCalls.single.sessionToken, s1);
    expect(ctrl.text, '15 Tahrir Square, Abdeen');
    expect(selected, isNotNull);
    expect(selected!.lat, closeTo(30.0444, 1e-9));

    // Starting a new search issues a new session token.
    await tester.enterText(find.byKey(const Key('test_addr_field')), 'Dokki');
    await tester.pump(const Duration(milliseconds: 450));
    expect(geo.autocompleteCalls, hasLength(3));
    expect(geo.autocompleteCalls[2].sessionToken, isNot(s1));
  });

  testWidgets('picker: picking a suggestion moves the pin and fills address',
      (tester) async {
    usePhone(tester);
    final geo = FakeGeoService(
      nextSuggestions: const [
        GeoSuggestion(
          placeId: 'ChIJ_dokki',
          primary: '4 Tahrir St',
          secondary: 'Dokki, Giza',
        ),
      ],
      nextPlace: const GeoPlace(
        lat: 30.0385,
        lng: 31.2121,
        address: '4 Tahrir St, Dokki',
        area: 'Dokki',
      ),
    );
    final results = <PickedPlace?>[];
    await tester.pumpWidget(
      GeoScope(
        service: geo,
        child: customerApp(
          CustomerTestDeps(),
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    results.add(await CustomerPickerPage.open(
                  ctx,
                  title: 'Drop-off place',
                  initial: const PickedPlace(latitude: 30.1, longitude: 31.3),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('cust_picker_address')), 'Dokki');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addr_suggestion_0')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cust_picker_confirm')));
    await tester.pumpAndSettle();

    expect(results.single, isNotNull);
    expect(results.single!.address, '4 Tahrir St, Dokki');
    expect(results.single!.latitude, closeTo(30.0385, 1e-6));
    expect(results.single!.longitude, closeTo(31.2121, 1e-6));
    // Programmatic move from picking a place must not fire reverse geocode.
    expect(geo.reverseCalls, isEmpty);
  });

  testWidgets('saved-address editor uses the same search field and sets pin',
      (tester) async {
    usePhone(tester);
    final geo = FakeGeoService(
      nextSuggestions: const [
        GeoSuggestion(
          placeId: 'ChIJ_maadi',
          primary: 'Road 9',
          secondary: 'Maadi, Cairo',
        ),
      ],
      nextPlace: const GeoPlace(
        lat: 29.9602,
        lng: 31.2564,
        address: 'Road 9, Maadi',
        area: 'Maadi',
      ),
    );
    final deps = acct.AccountTestDeps(
      auth: acct.FakeAuthFlow(
          user:
              acct.FakeAuthFlow.customer(saved: const [], addresses: const [])),
    );
    await tester.pumpWidget(
      GeoScope(
        service: geo,
        child: acct.accountApp(deps, const SavedAddressesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addresses_add')));
    await tester.pumpAndSettle();

    expect(find.byType(AddressSearchField), findsOneWidget);

    await tester.enterText(find.byKey(const Key('address_input')), 'Road 9');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addr_suggestion_0')));
    await tester.pumpAndSettle();

    expect(find.text('Road 9, Maadi'), findsOneWidget);
    expect(find.text('29.9602, 31.2564'), findsOneWidget);

    await tester.tap(find.byKey(const Key('address_save')));
    await tester.pumpAndSettle();

    final sent = deps.auth.lastProfileUpdate?['saved_addresses'] as List?;
    expect(sent, hasLength(1));
    expect(sent!.first['address'], 'Road 9, Maadi');
    expect(sent.first['latitude'], closeTo(29.9602, 1e-6));
    expect(sent.first['longitude'], closeTo(31.2564, 1e-6));
  });

  test('ApiGeoService sends query params, Accept-Language, and maps errors',
      () async {
    final seen = <http.Request>[];
    var statusToReturn = 200;
    var bodyToReturn = jsonEncode({
      'suggestions': [
        {'place_id': 'p1', 'primary': 'Street 1', 'secondary': 'Cairo'},
      ],
    });

    final client = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      client: MockClient((req) async {
        seen.add(req);
        return http.Response(bodyToReturn, statusToReturn);
      }),
    );
    final svc = ApiGeoService(client);

    final list = await svc.autocomplete(
        query: 'Tahrir', sessionToken: 's1', languageCode: 'ar');
    expect(list.single.placeId, 'p1');
    expect(seen.last.url.path, '/api/v1/users/geo/autocomplete');
    expect(seen.last.url.queryParameters, {'q': 'Tahrir', 'session': 's1'});
    expect(seen.last.headers['Accept-Language'], 'ar');

    statusToReturn = 503;
    bodyToReturn = jsonEncode({'code': 'geo_unavailable', 'error': 'down'});
    await expectLater(
      svc.autocomplete(query: 'Tahrir', sessionToken: 's2', languageCode: 'en'),
      throwsA(isA<GeoException>()
          .having((e) => e.kind, 'kind', GeoFailureKind.unavailable)),
    );

    statusToReturn = 429;
    bodyToReturn = jsonEncode({'code': 'rate_limited', 'error': 'slow down'});
    await expectLater(
      svc.reverseGeocode(latitude: 30.04, longitude: 31.23, languageCode: 'en'),
      throwsA(isA<GeoException>()
          .having((e) => e.kind, 'kind', GeoFailureKind.rateLimited)),
    );
  });
}
