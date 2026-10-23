import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/location_permission.dart';
import '../../models/job.dart';

/// Where the app looks when the device location is unknown (Cairo, the same
/// default as MarketplaceProvider.fetchServices).
const double kDefaultLatitude = 30.0444;
const double kDefaultLongitude = 31.2357;

/// A place the customer chose: coordinates, optional address text (job
/// model v2) and landmark note, and whether it came from the device
/// location (shown as "Your current location" instead of "Pinned
/// location").
@immutable
class PickedPlace {
  const PickedPlace({
    required this.latitude,
    required this.longitude,
    this.note,
    this.address,
    this.isDeviceLocation = false,
  });

  final double latitude;
  final double longitude;
  final String? note;

  /// Street / building / area text (ADR-0028 §2.2), typed in the picker.
  final String? address;
  final bool isDeviceLocation;

  String? get trimmedNote {
    final n = note?.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  String? get trimmedAddress {
    final a = address?.trim() ?? '';
    return a.isEmpty ? null : a;
  }

  PickedPlace copyWith({String? note, String? address}) => PickedPlace(
        latitude: latitude,
        longitude: longitude,
        note: note ?? this.note,
        address: address ?? this.address,
        isDeviceLocation: isDeviceLocation,
      );

  JobLocation toJobLocation() => JobLocation(
      latitude: latitude,
      longitude: longitude,
      addressNote: trimmedNote,
      address: trimmedAddress);

  @override
  bool operator ==(Object other) =>
      other is PickedPlace &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.note == note &&
      other.address == address &&
      other.isDeviceLocation == isDeviceLocation;

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, note, address, isDeviceLocation);
}

enum LocateStatus { found, denied, unavailable }

@immutable
class LocateResult {
  const LocateResult.found(double lat, double lon)
      : status = LocateStatus.found,
        latitude = lat,
        longitude = lon;
  const LocateResult.denied()
      : status = LocateStatus.denied,
        latitude = null,
        longitude = null;
  const LocateResult.unavailable()
      : status = LocateStatus.unavailable,
        latitude = null,
        longitude = null;

  final LocateStatus status;
  final double? latitude;
  final double? longitude;

  PickedPlace? get place => status == LocateStatus.found
      ? PickedPlace(
          latitude: latitude!, longitude: longitude!, isDeviceLocation: true)
      : null;
}

/// Gets the device location for the customer screens. Swappable through
/// [CustomerLocatorScope] so tests never touch the platform channel.
abstract class CustomerLocator {
  const CustomerLocator();

  Future<LocateResult> locate();
}

class DeviceCustomerLocator extends CustomerLocator {
  const DeviceCustomerLocator();

  @override
  Future<LocateResult> locate() async {
    try {
      final perm = await requestLocationPermission();
      switch (perm) {
        case LocationPermissionResult.granted:
          final pos = await Geolocator.getCurrentPosition();
          return LocateResult.found(pos.latitude, pos.longitude);
        case LocationPermissionResult.denied:
        case LocationPermissionResult.deniedForever:
          return const LocateResult.denied();
        case LocationPermissionResult.serviceDisabled:
          return const LocateResult.unavailable();
      }
    } catch (_) {
      return const LocateResult.unavailable();
    }
  }
}

/// Provides a [CustomerLocator] to the customer screens below it (including
/// pushed routes when placed above the navigator).
class CustomerLocatorScope extends InheritedWidget {
  const CustomerLocatorScope(
      {super.key, required this.locator, required super.child});

  final CustomerLocator locator;

  static CustomerLocator of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CustomerLocatorScope>()
          ?.locator ??
      const DeviceCustomerLocator();

  @override
  bool updateShouldNotify(CustomerLocatorScope oldWidget) =>
      locator != oldWidget.locator;
}
