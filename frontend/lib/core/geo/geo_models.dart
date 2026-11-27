import 'package:flutter/foundation.dart';

/// A single address autocomplete suggestion returned by `/users/geo/autocomplete`.
@immutable
class GeoSuggestion {
  const GeoSuggestion({
    required this.placeId,
    required this.primary,
    this.secondary = '',
  });

  factory GeoSuggestion.fromJson(Map<String, dynamic> json) => GeoSuggestion(
        placeId: (json['place_id'] as String? ?? '').trim(),
        primary: (json['primary'] as String? ?? '').trim(),
        secondary: (json['secondary'] as String? ?? '').trim(),
      );

  final String placeId;
  final String primary;
  final String secondary;

  @override
  bool operator ==(Object other) =>
      other is GeoSuggestion &&
      other.placeId == placeId &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(placeId, primary, secondary);
}

/// Resolved coordinates and address text returned by `/users/geo/place`.
@immutable
class GeoPlace {
  const GeoPlace({
    required this.lat,
    required this.lng,
    required this.address,
    this.area = '',
  });

  factory GeoPlace.fromJson(Map<String, dynamic> json) => GeoPlace(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        address: (json['address'] as String? ?? '').trim(),
        area: (json['area'] as String? ?? '').trim(),
      );

  final double lat;
  final double lng;
  final String address;
  final String area;

  @override
  bool operator ==(Object other) =>
      other is GeoPlace &&
      other.lat == lat &&
      other.lng == lng &&
      other.address == address &&
      other.area == area;

  @override
  int get hashCode => Object.hash(lat, lng, address, area);
}

/// Reverse-geocoded address text returned by `/users/geo/reverse`.
@immutable
class GeoReverseResult {
  const GeoReverseResult({
    required this.address,
    this.area = '',
  });

  factory GeoReverseResult.fromJson(Map<String, dynamic> json) =>
      GeoReverseResult(
        address: (json['address'] as String? ?? '').trim(),
        area: (json['area'] as String? ?? '').trim(),
      );

  final String address;
  final String area;

  @override
  bool operator ==(Object other) =>
      other is GeoReverseResult &&
      other.address == address &&
      other.area == area;

  @override
  int get hashCode => Object.hash(address, area);
}

enum GeoFailureKind {
  unavailable,
  rateLimited,
  network,
  other,
}

class GeoException implements Exception {
  const GeoException(
    this.kind, {
    this.statusCode,
    this.errorCode,
  });

  final GeoFailureKind kind;
  final int? statusCode;
  final String? errorCode;

  @override
  String toString() =>
      'GeoException($kind, status: $statusCode, code: $errorCode)';
}
