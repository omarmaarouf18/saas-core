import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/models/job.dart';

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

}
