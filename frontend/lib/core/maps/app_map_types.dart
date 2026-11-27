import 'package:flutter/widgets.dart';

/// Maps SDK API key compiled via `--dart-define=MAPS_API_KEY=...`.
/// Empty by default so local development and unkeyed CI builds still work;
/// when empty (and no test fake is injected), [AppMap] renders an unavailable
/// state instead of mounting a native map view.
const String kMapsApiKey = String.fromEnvironment('MAPS_API_KEY');

/// Whether a Maps SDK API key was supplied at compile time.
bool get defaultHasMapsApiKey => kMapsApiKey.isNotEmpty;

/// Immutable latitude/longitude pair owned by the app's map wrapper so feature
/// screens never import map plugin types directly.
@immutable
class AppLatLng {
  const AppLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is AppLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'AppLatLng($latitude, $longitude)';
}

/// Visual variants for markers rendered on [AppMap].
enum AppMarkerKind {
  pickupRing,
  dropoffSquare,
  selfDot,
  courierPin,
  fleetCourier,
}

/// Declarative visual specification for an [AppMapMarker], shared between the
/// real Google Maps bitmap rasterizer and the test fake widget renderer.
@immutable
class AppMarkerIcon {
  const AppMarkerIcon.pickupRing()
      : kind = AppMarkerKind.pickupRing,
        initial = '',
        onJob = false,
        selected = false,
        size = const Size(22, 22);

  const AppMarkerIcon.dropoffSquare()
      : kind = AppMarkerKind.dropoffSquare,
        initial = '',
        onJob = false,
        selected = false,
        size = const Size(22, 22);

  const AppMarkerIcon.selfDot()
      : kind = AppMarkerKind.selfDot,
        initial = '',
        onJob = false,
        selected = false,
        size = const Size(28, 28);

  const AppMarkerIcon.courierPin()
      : kind = AppMarkerKind.courierPin,
        initial = '',
        onJob = false,
        selected = false,
        size = const Size(36, 36);

  AppMarkerIcon.fleetCourier({
    required this.initial,
    required this.onJob,
    this.selected = false,
  })  : kind = AppMarkerKind.fleetCourier,
        size = Size.square(selected ? 44 : 36);

  final AppMarkerKind kind;
  final String initial;
  final bool onJob;
  final bool selected;
  final Size size;

  @override
  bool operator ==(Object other) =>
      other is AppMarkerIcon &&
      other.kind == kind &&
      other.initial == initial &&
      other.onJob == onJob &&
      other.selected == selected &&
      other.size == size;

  @override
  int get hashCode => Object.hash(kind, initial, onJob, selected, size);
}

/// A marker displayed on [AppMap].
@immutable
class AppMapMarker {
  const AppMapMarker({
    required this.id,
    required this.position,
    required this.icon,
    this.markerKey,
    this.semanticLabel,
    this.selected = false,
    this.anchor = const Offset(0.5, 0.5),
    this.onTap,
  });

  final String id;
  final AppLatLng position;
  final AppMarkerIcon icon;
  final Key? markerKey;
  final String? semanticLabel;
  final bool selected;
  final Offset anchor;
  final VoidCallback? onTap;
}

/// A polyline displayed on [AppMap].
@immutable
class AppMapPolyline {
  const AppMapPolyline({
    required this.id,
    required this.points,
    required this.color,
    this.width = 4,
  });

  final String id;
  final List<AppLatLng> points;
  final Color color;
  final double width;
}

/// Configuration snapshot passed to [AppMapViewBuilder] (used by test fakes).
@immutable
class AppMapConfig {
  const AppMapConfig({
    required this.initialCenter,
    required this.initialZoom,
    required this.initialBounds,
    required this.initialBoundsPadding,
    required this.markers,
    required this.polylines,
    required this.interactive,
    required this.rotateEnabled,
    required this.padding,
    required this.mapStyle,
    required this.semanticLabel,
    required this.onMapReady,
    required this.onCameraMoveStarted,
    required this.onCameraMove,
    required this.onCameraIdle,
    required this.onTap,
  });

  final AppLatLng initialCenter;
  final double initialZoom;
  final List<AppLatLng>? initialBounds;
  final EdgeInsets initialBoundsPadding;
  final List<AppMapMarker> markers;
  final List<AppMapPolyline> polylines;
  final bool interactive;
  final bool rotateEnabled;
  final EdgeInsets padding;
  final String? mapStyle;
  final String? semanticLabel;
  final VoidCallback? onMapReady;
  final VoidCallback? onCameraMoveStarted;
  final ValueChanged<AppLatLng>? onCameraMove;
  final ValueChanged<AppLatLng>? onCameraIdle;
  final ValueChanged<AppLatLng>? onTap;
}

/// Platform-agnostic handle attached to [AppMapController] by either the real
/// Google Maps host or a test fake map widget.
abstract class AppMapHandle {
  AppLatLng get center;
  double get zoom;
  void move(AppLatLng target, {double? zoom});
  void fitBounds(List<AppLatLng> points, {required EdgeInsets padding});
  void zoomBy(double delta);
}

/// Imperative camera controller for [AppMap].
class AppMapController {
  AppMapHandle? _handle;

  /// Whether the underlying map view has attached and is ready for commands.
  bool get isReady => _handle != null;

  /// Current camera centre, or null before the map attaches.
  AppLatLng? get center => _handle?.center;

  /// Current camera zoom, or `0` before the map attaches.
  double get zoom => _handle?.zoom ?? 0;

  void attach(AppMapHandle handle) {
    _handle = handle;
  }

  void detach(AppMapHandle handle) {
    if (identical(_handle, handle)) {
      _handle = null;
    }
  }

  /// Moves the camera to [target], preserving the current zoom when [zoom] is omitted.
  void move(AppLatLng target, {double? zoom}) {
    _handle?.move(target, zoom: zoom);
  }

  /// Fits the camera around [points] with [padding]. Single/identical points
  /// fall back to centering at zoom 15.
  void fitBounds(
    List<AppLatLng> points, {
    EdgeInsets padding = const EdgeInsets.all(40),
  }) {
    if (points.isEmpty) return;
    _handle?.fitBounds(points, padding: padding);
  }

  /// Adjusts zoom level by [delta].
  void zoomBy(double delta) {
    _handle?.zoomBy(delta);
  }

  void dispose() {
    _handle = null;
  }
}
