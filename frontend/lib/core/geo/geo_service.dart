import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api_client.dart';
import 'geo_models.dart';

/// Client interface for server-proxied Google Maps address search and
/// reverse geocoding (`/users/geo/*`).
abstract class GeoService {
  const GeoService();

  Future<List<GeoSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    required String languageCode,
  });

  Future<GeoPlace> placeDetails({
    required String placeId,
    required String sessionToken,
    required String languageCode,
  });

  Future<GeoReverseResult> reverseGeocode({
    required double latitude,
    required double longitude,
    required String languageCode,
  });
}

/// Production [GeoService] backed by [ApiClient].
class ApiGeoService extends GeoService {
  const ApiGeoService(this.apiClient);

  final ApiClient apiClient;

  static String _normalizeLang(String languageCode) =>
      languageCode.toLowerCase().startsWith('ar') ? 'ar' : 'en';

  GeoException _mapError(Object error) {
    if (error is GeoException) return error;
    if (error is ApiClientException) {
      final code = error.errorCode;
      final status = error.statusCode;
      if (code == 'geo_unavailable' || status == 503) {
        return GeoException(
          GeoFailureKind.unavailable,
          statusCode: status,
          errorCode: code,
        );
      }
      if (status == 429 ||
          code == 'rate_limited' ||
          code == 'geo_rate_limited') {
        return GeoException(
          GeoFailureKind.rateLimited,
          statusCode: status,
          errorCode: code,
        );
      }
      if (status == null) {
        return GeoException(GeoFailureKind.network, errorCode: code);
      }
      return GeoException(
        GeoFailureKind.other,
        statusCode: status,
        errorCode: code,
      );
    }
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException ||
        error is HandshakeException ||
        error is TlsException ||
        error is http.ClientException) {
      return const GeoException(GeoFailureKind.network);
    }
    return const GeoException(GeoFailureKind.other);
  }

  @override
  Future<List<GeoSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    required String languageCode,
  }) async {
    try {
      final res = await apiClient.get(
        '/users/geo/autocomplete',
        queryParams: {
          'q': query,
          if (sessionToken.isNotEmpty) 'session': sessionToken,
        },
        headers: {'Accept-Language': _normalizeLang(languageCode)},
      );
      if (res is Map && res['suggestions'] is List) {
        return (res['suggestions'] as List)
            .whereType<Map<String, dynamic>>()
            .map(GeoSuggestion.fromJson)
            .where((s) => s.placeId.isNotEmpty && s.primary.isNotEmpty)
            .toList();
      }
      return const [];
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<GeoPlace> placeDetails({
    required String placeId,
    required String sessionToken,
    required String languageCode,
  }) async {
    try {
      final res = await apiClient.get(
        '/users/geo/place',
        queryParams: {
          'place_id': placeId,
          if (sessionToken.isNotEmpty) 'session': sessionToken,
        },
        headers: {'Accept-Language': _normalizeLang(languageCode)},
      );
      if (res is Map<String, dynamic>) {
        return GeoPlace.fromJson(res);
      }
      throw const GeoException(GeoFailureKind.other);
    } catch (e) {
      throw _mapError(e);
    }
  }

  @override
  Future<GeoReverseResult> reverseGeocode({
    required double latitude,
    required double longitude,
    required String languageCode,
  }) async {
    try {
      final res = await apiClient.get(
        '/users/geo/reverse',
        queryParams: {
          'lat': latitude.toStringAsFixed(6),
          'lng': longitude.toStringAsFixed(6),
        },
        headers: {'Accept-Language': _normalizeLang(languageCode)},
      );
      if (res is Map<String, dynamic>) {
        return GeoReverseResult.fromJson(res);
      }
      throw const GeoException(GeoFailureKind.other);
    } catch (e) {
      throw _mapError(e);
    }
  }
}

/// Supplies [GeoService] to picker and saved-address screens (swapped in tests).
class GeoScope extends InheritedWidget {
  const GeoScope({
    super.key,
    required this.service,
    required super.child,
  });

  final GeoService? service;

  static GeoService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GeoScope>()?.service;

  @override
  bool updateShouldNotify(GeoScope oldWidget) => service != oldWidget.service;
}
