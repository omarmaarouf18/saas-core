import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/core/location_permission.dart';

class MockGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission initialPermission = LocationPermission.denied;
  LocationPermission requestedPermission = LocationPermission.whileInUse;

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => initialPermission;

  @override
  Future<LocationPermission> requestPermission() async => requestedPermission;
}

void main() {
  late MockGeolocatorPlatform mockGeolocator;

  setUp(() {
    mockGeolocator = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mockGeolocator;
  });

  test('returns serviceDisabled when location services are disabled', () async {
    mockGeolocator.isServiceEnabled = false;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.serviceDisabled);
  });

  test('returns granted when initial permission is whileInUse', () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.whileInUse;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.granted);
  });

  test('returns granted when initial permission is always', () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.always;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.granted);
  });

  test('requests permission when denied and returns granted when user accepts',
      () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.denied;
    mockGeolocator.requestedPermission = LocationPermission.whileInUse;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.granted);
  });

  test('returns denied when user denies permission request', () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.denied;
    mockGeolocator.requestedPermission = LocationPermission.denied;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.denied);
  });

  test('returns deniedForever when initial permission is deniedForever',
      () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.deniedForever;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.deniedForever);
  });

  test('returns denied when permission is unableToDetermine', () async {
    mockGeolocator.isServiceEnabled = true;
    mockGeolocator.initialPermission = LocationPermission.unableToDetermine;

    final result = await requestLocationPermission();
    expect(result, LocationPermissionResult.denied);
  });
}
