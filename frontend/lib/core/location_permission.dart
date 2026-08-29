import 'package:geolocator/geolocator.dart';

enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Requests device location permission and returns a unified [LocationPermissionResult].
///
/// Wraps [GeolocatorPlatform] check and request flow.
/// 1. Checks if location services (GPS) are enabled.
/// 2. Checks current permission state, requesting permission if currently denied.
/// 3. Maps the resulting permission state to [LocationPermissionResult].
Future<LocationPermissionResult> requestLocationPermission({
  GeolocatorPlatform? platform,
}) async {
  final geolocator = platform ?? GeolocatorPlatform.instance;

  try {
    final bool serviceEnabled = await geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionResult.serviceDisabled;
    }

    LocationPermission permission = await geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionResult.granted;
      case LocationPermission.denied:
        return LocationPermissionResult.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionResult.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionResult.denied;
    }
  } catch (_) {
    return LocationPermissionResult.serviceDisabled;
  }
}
