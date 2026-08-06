import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/widgets/location_picker_map.dart';

Widget createLocationApp({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: child,
      ),
    ),
  );
}

class MockGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission initialPermission = LocationPermission.denied;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Position mockPosition = Position(
    latitude: 31.2001,
    longitude: 29.9187,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => initialPermission;

  @override
  Future<LocationPermission> requestPermission() async => requestedPermission;

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      mockPosition;
}

void main() {
  late MockGeolocatorPlatform mockGeolocator;

  setUp(() {
    mockGeolocator = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mockGeolocator;
  });

  testWidgets(
      '(a) Defaults to initialLocation or Cairo default when un-fetched',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      createLocationApp(
        child: const LocationPickerMap(
          initialLocation: LatLng(30.0444, 31.2357),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_marker')), findsOneWidget);
    expect(
        find.byKey(const Key('use_current_location_button')), findsOneWidget);
  });

  testWidgets(
      '(b) Falls back to Cairo default and shows snackbar when location permission is denied',
      (WidgetTester tester) async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.denied;
    mockGeolocator.requestedPermission = LocationPermission.denied;

    await tester.pumpWidget(
      createLocationApp(
        child: LocationPickerMap(
          geolocatorPlatform: mockGeolocator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final useLocationBtn = find.byKey(const Key('use_current_location_button'));
    expect(useLocationBtn, findsOneWidget);
    await tester.tap(useLocationBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("Location permission denied. Defaulting to Cairo."),
        findsOneWidget);
  });

  testWidgets(
      '(c) Tapping location_picker_marker fires onLocationSelected callback',
      (WidgetTester tester) async {
    LatLng? selected;

    await tester.pumpWidget(
      createLocationApp(
        child: LocationPickerMap(
          initialLocation: const LatLng(30.0444, 31.2357),
          onLocationSelected: (latLng) {
            selected = latLng;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final markerFinder = find.byKey(const Key('location_picker_marker'));
    expect(markerFinder, findsOneWidget);
    await tester.tap(markerFinder);
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
  });

  testWidgets(
      '(d) Use my current location button re-centers when permission granted',
      (WidgetTester tester) async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.whileInUse;

    LatLng? selected;

    await tester.pumpWidget(
      createLocationApp(
        child: LocationPickerMap(
          initialLocation: const LatLng(30.0444, 31.2357),
          geolocatorPlatform: mockGeolocator,
          onLocationSelected: (latLng) {
            selected = latLng;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final useLocationBtn = find.byKey(const Key('use_current_location_button'));
    await tester.tap(useLocationBtn);
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.latitude, 31.2001);
    expect(selected!.longitude, 29.9187);
  });

  testWidgets(
      '(e) Renders overflow-free inside narrow mobile container bounds (330x480)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 330,
            height: 480,
            child: LocationPickerMap(
              initialLocation: LatLng(30.0444, 31.2357),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_marker')), findsOneWidget);
    expect(
        find.byKey(const Key('use_current_location_button')), findsOneWidget);
  });
}
