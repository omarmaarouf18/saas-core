import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/screens/employee_job_map_screen.dart';

import 'helpers/stub_tile_http.dart';

class MockGeolocatorPlatformForEmployeeMap extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  Position? fixedPosition;
  final StreamController<Position> positionStreamController =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    return fixedPosition ?? makePosition(30.002, 31.002);
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return positionStreamController.stream;
  }
}

Position makePosition(double lat, double lng) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

Job makeMapJob({String? destinationNote}) {
  return Job(
    id: 'job-map-1',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'active',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    destination: JobLocation(
      latitude: 30.005,
      longitude: 31.005,
      addressNote: destinationNote,
    ),
    paymentMethod: 'cod',
  );
}

Widget buildMapTestApp({
  required Job job,
  required MockGeolocatorPlatformForEmployeeMap mockGeolocator,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: EmployeeJobMapScreen(
      job: job,
      geolocatorPlatform: mockGeolocator,
    ),
  );
}

/// Settles the map screen: the resolving pulse (PendingPulseDot) is
/// transient — permission resolves to granted/denied/error — so the final
/// state is static and pumpAndSettle terminates.
Future<void> settleMapFrames(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = StubTileHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  group('JobLocation.addressSummary', () {
    test('returns the typed note when present', () {
      final loc = JobLocation(
        latitude: 30.0,
        longitude: 31.0,
        addressNote: "beside Ahmed's kiosk",
      );
      expect(loc.addressSummary(), "beside Ahmed's kiosk");
    });

    test('blank note falls back to coordinates', () {
      final loc = JobLocation(
        latitude: 30.5,
        longitude: 31.25,
        addressNote: '   ',
      );
      expect(loc.addressSummary(), '30.5000, 31.2500');
    });

    test('falls back to coordinates when no note was entered', () {
      final loc = JobLocation(latitude: 30.0, longitude: 31.0);
      expect(loc.addressSummary(), '30.0000, 31.0000');
    });
  });

  group('EmployeeJobMapScreen', () {
    testWidgets('renders pickup + dropoff + live self markers with addresses',
        (WidgetTester tester) async {
      final mockGeolocator = MockGeolocatorPlatformForEmployeeMap();
      final job = makeMapJob(destinationNote: "beside Ahmed's kiosk");

      await tester.pumpWidget(buildMapTestApp(
        job: job,
        mockGeolocator: mockGeolocator,
      ));
      await settleMapFrames(tester);

      // All three ends on one live map.
      expect(
          find.byKey(const Key('employee_map_pickup_marker')), findsOneWidget);
      expect(
          find.byKey(const Key('employee_map_dropoff_marker')), findsOneWidget);
      expect(find.byKey(const Key('employee_map_self_marker')), findsOneWidget);
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Dropoff'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byIcon(Icons.person_pin_circle), findsOneWidget);

      // Address sheet: note-primary dropoff, coords-only pickup (no note).
      expect(find.text("beside Ahmed's kiosk"), findsOneWidget);
      expect(find.text('30.0000, 31.0000'), findsOneWidget);
      expect(find.text('Live Trip Map'), findsOneWidget);
    });

    testWidgets('live self marker follows position-stream updates',
        (WidgetTester tester) async {
      final mockGeolocator = MockGeolocatorPlatformForEmployeeMap();

      await tester.pumpWidget(buildMapTestApp(
        job: makeMapJob(),
        mockGeolocator: mockGeolocator,
      ));
      await settleMapFrames(tester);

      // flutter_map v7 Marker is a data object, not a Widget: the key is
      // passed through to the built marker widget, so presence (not the
      // point itself) is what the tree can assert. The stream update must
      // rebuild exactly one self marker without crashing or duplicating.
      // (Nearby fix: MarkerLayer culls off-viewport markers, so a far
      // jump would leave the tree even though tracking still works.)
      final selfKey = find.byKey(const Key('employee_map_self_marker'));
      expect(selfKey, findsOneWidget);

      mockGeolocator.positionStreamController.add(makePosition(30.003, 31.003));
      await settleMapFrames(tester);

      expect(selfKey, findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets(
        'permission denied degrades gracefully: denied banner, trip markers stay, no crash',
        (WidgetTester tester) async {
      final mockGeolocator = MockGeolocatorPlatformForEmployeeMap()
        ..permission = LocationPermission.denied;

      await tester.pumpWidget(buildMapTestApp(
        job: makeMapJob(),
        mockGeolocator: mockGeolocator,
      ));
      await settleMapFrames(tester);

      expect(find.byKey(const Key('employee_map_location_denied_banner')),
          findsOneWidget);
      // Trip ends still render — only the "you" marker is missing.
      expect(
          find.byKey(const Key('employee_map_pickup_marker')), findsOneWidget);
      expect(
          find.byKey(const Key('employee_map_dropoff_marker')), findsOneWidget);
      expect(find.byKey(const Key('employee_map_self_marker')), findsNothing);
    });

    testWidgets('null destination: no dropoff marker, fallback address text',
        (WidgetTester tester) async {
      final mockGeolocator = MockGeolocatorPlatformForEmployeeMap();
      final job = Job(
        id: 'job-map-2',
        ownerId: 'owner-1',
        employeeId: 'emp-1',
        userId: 'cust-1',
        serviceId: 'service-1',
        status: 'active',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        paymentMethod: 'cod',
      );

      await tester.pumpWidget(buildMapTestApp(
        job: job,
        mockGeolocator: mockGeolocator,
      ));
      await settleMapFrames(tester);

      expect(
          find.byKey(const Key('employee_map_pickup_marker')), findsOneWidget);
      expect(
          find.byKey(const Key('employee_map_dropoff_marker')), findsNothing);
      expect(find.text('Dropoff'), findsNothing);
      expect(find.text('Destination not set yet'), findsOneWidget);
    });
  });
}
