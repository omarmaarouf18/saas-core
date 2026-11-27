import 'dart:async';

import 'package:frontend/core/geo/geo_models.dart';
import 'package:frontend/core/geo/geo_service.dart';

class AutocompleteCall {
  const AutocompleteCall({
    required this.query,
    required this.sessionToken,
    required this.languageCode,
  });

  final String query;
  final String sessionToken;
  final String languageCode;
}

class PlaceCall {
  const PlaceCall({
    required this.placeId,
    required this.sessionToken,
    required this.languageCode,
  });

  final String placeId;
  final String sessionToken;
  final String languageCode;
}

class ReverseCall {
  const ReverseCall({
    required this.latitude,
    required this.longitude,
    required this.languageCode,
  });

  final double latitude;
  final double longitude;
  final String languageCode;
}

class FakeGeoService extends GeoService {
  FakeGeoService({
    this.nextSuggestions = const [
      GeoSuggestion(
        placeId: 'ChIJ_tahrir',
        primary: '15 Tahrir Square',
        secondary: 'Downtown, Cairo, Egypt',
      ),
    ],
    this.nextPlace = const GeoPlace(
      lat: 30.0444,
      lng: 31.2357,
      address: '15 Tahrir Square, Abdeen',
      area: 'Abdeen',
    ),
    this.nextReverse = const GeoReverseResult(
      address: '26 July Corridor, Zamalek',
      area: 'Zamalek',
    ),
  });

  List<GeoSuggestion> nextSuggestions;
  GeoPlace nextPlace;
  GeoReverseResult nextReverse;

  Object? autocompleteError;
  Object? placeError;
  Object? reverseError;

  Completer<void>? autocompleteGate;
  Completer<void>? placeGate;
  Completer<void>? reverseGate;

  final List<AutocompleteCall> autocompleteCalls = [];
  final List<PlaceCall> placeCalls = [];
  final List<ReverseCall> reverseCalls = [];

  @override
  Future<List<GeoSuggestion>> autocomplete({
    required String query,
    required String sessionToken,
    required String languageCode,
  }) async {
    autocompleteCalls.add(AutocompleteCall(
      query: query,
      sessionToken: sessionToken,
      languageCode: languageCode,
    ));
    if (autocompleteGate != null) await autocompleteGate!.future;
    if (autocompleteError != null) throw autocompleteError!;
    return nextSuggestions;
  }

  @override
  Future<GeoPlace> placeDetails({
    required String placeId,
    required String sessionToken,
    required String languageCode,
  }) async {
    placeCalls.add(PlaceCall(
      placeId: placeId,
      sessionToken: sessionToken,
      languageCode: languageCode,
    ));
    if (placeGate != null) await placeGate!.future;
    if (placeError != null) throw placeError!;
    return nextPlace;
  }

  @override
  Future<GeoReverseResult> reverseGeocode({
    required double latitude,
    required double longitude,
    required String languageCode,
  }) async {
    reverseCalls.add(ReverseCall(
      latitude: latitude,
      longitude: longitude,
      languageCode: languageCode,
    ));
    if (reverseGate != null) await reverseGate!.future;
    if (reverseError != null) throw reverseError!;
    return nextReverse;
  }
}
