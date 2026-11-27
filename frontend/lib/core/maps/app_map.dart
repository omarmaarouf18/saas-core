import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import 'app_map_types.dart';
import 'map_marker_renderer.dart';
import 'waddify_map_style.dart';

export 'app_map_types.dart';

/// Builder hook used by [AppMapScope] and [AppMap.mapBuilder] so widget tests
/// can inject a fake map without touching native platform views.
typedef AppMapViewBuilder = Widget Function(
  BuildContext context,
  AppMapConfig config,
  AppMapController controller,
);

/// Supplies a test map builder and/or API-key availability override to all
/// [AppMap] widgets below it.
class AppMapScope extends InheritedWidget {
  const AppMapScope({
    super.key,
    this.builder,
    this.hasApiKey,
    required super.child,
  });

  final AppMapViewBuilder? builder;
  final bool? hasApiKey;

  static AppMapScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppMapScope>();

  @override
  bool updateShouldNotify(AppMapScope oldWidget) =>
      builder != oldWidget.builder || hasApiKey != oldWidget.hasApiKey;
}

/// Single map widget used across all Waddify client screens. Wraps
/// `google_maps_flutter` so feature screens never import the plugin directly.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
    this.initialBounds,
    this.initialBoundsPadding = const EdgeInsets.all(32),
    this.controller,
    this.markers = const [],
    this.polylines = const [],
    this.interactive = true,
    this.rotateEnabled = false,
    this.padding = EdgeInsets.zero,
    this.mapStyle,
    this.semanticLabel,
    this.hasApiKey,
    this.mapBuilder,
    this.onMapReady,
    this.onCameraMoveStarted,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
  });

  final AppLatLng initialCenter;
  final double initialZoom;
  final List<AppLatLng>? initialBounds;
  final EdgeInsets initialBoundsPadding;
  final AppMapController? controller;
  final List<AppMapMarker> markers;
  final List<AppMapPolyline> polylines;
  final bool interactive;
  final bool rotateEnabled;
  final EdgeInsets padding;
  final String? mapStyle;
  final String? semanticLabel;

  /// Explicit override for whether a Maps SDK API key is configured (tests).
  final bool? hasApiKey;

  /// Explicit fake map builder override (tests).
  final AppMapViewBuilder? mapBuilder;

  final VoidCallback? onMapReady;
  final VoidCallback? onCameraMoveStarted;
  final ValueChanged<AppLatLng>? onCameraMove;
  final ValueChanged<AppLatLng>? onCameraIdle;
  final ValueChanged<AppLatLng>? onTap;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  AppMapController? _ownedController;

  AppMapController get _controller =>
      widget.controller ?? (_ownedController ??= AppMapController());

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppMapScope.maybeOf(context);
    final configured =
        widget.hasApiKey ?? scope?.hasApiKey ?? defaultHasMapsApiKey;

    Widget content;
    if (!configured) {
      content = const _MapUnavailableView();
    } else {
      final config = AppMapConfig(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        initialBounds: widget.initialBounds,
        initialBoundsPadding: widget.initialBoundsPadding,
        markers: widget.markers,
        polylines: widget.polylines,
        interactive: widget.interactive,
        rotateEnabled: widget.rotateEnabled,
        padding: widget.padding,
        mapStyle: widget.mapStyle,
        semanticLabel: widget.semanticLabel,
        onMapReady: widget.onMapReady,
        onCameraMoveStarted: widget.onCameraMoveStarted,
        onCameraMove: widget.onCameraMove,
        onCameraIdle: widget.onCameraIdle,
        onTap: widget.onTap,
      );
      final builder = widget.mapBuilder ?? scope?.builder;
      if (builder != null) {
        content = builder(context, config, _controller);
      } else {
        content = _GoogleMapHost(config: config, controller: _controller);
      }
    }

    if (widget.semanticLabel case final label?) {
      return Semantics(label: label, container: true, child: content);
    }
    return content;
  }
}

class _MapUnavailableView extends StatelessWidget {
  const _MapUnavailableView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Container(
      key: const Key('app_map_unavailable'),
      color: c.fillMuted,
      padding: const EdgeInsets.all(QdSpace.x4),
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showBody = constraints.maxHeight >= 140;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined,
                  size: QdSize.iconLg, color: c.textSecondary),
              const SizedBox(height: QdSpace.x2),
              Text(
                l10n.mapUnavailableTitle,
                textAlign: TextAlign.center,
                style: QdText.rowTitleSm.copyWith(color: c.textPrimary),
              ),
              if (showBody) ...[
                const SizedBox(height: QdSpace.x1),
                Text(
                  l10n.mapUnavailableBody,
                  textAlign: TextAlign.center,
                  style: QdText.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GoogleMapHost extends StatefulWidget {
  const _GoogleMapHost({required this.config, required this.controller});

  final AppMapConfig config;
  final AppMapController controller;

  @override
  State<_GoogleMapHost> createState() => _GoogleMapHostState();
}

class _GoogleMapHostState extends State<_GoogleMapHost>
    implements AppMapHandle {
  final AppMarkerBitmapCache _iconCache = AppMarkerBitmapCache();
  gmf.GoogleMapController? _gmf;
  late AppLatLng _center = widget.config.initialCenter;
  late double _zoom = widget.config.initialZoom;

  @override
  AppLatLng get center => _center;

  @override
  double get zoom => _zoom;

  @override
  void dispose() {
    widget.controller.detach(this);
    _gmf?.dispose();
    super.dispose();
  }

  gmf.LatLng _toGmf(AppLatLng p) => gmf.LatLng(p.latitude, p.longitude);

  @override
  void move(AppLatLng target, {double? zoom}) {
    final nextZoom = zoom ?? _zoom;
    _center = target;
    _zoom = nextZoom;
    _gmf?.moveCamera(gmf.CameraUpdate.newLatLngZoom(_toGmf(target), nextZoom));
  }

  @override
  void fitBounds(List<AppLatLng> points, {required EdgeInsets padding}) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      move(points.first, zoom: 15);
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLon = points.first.longitude;
    var maxLon = points.first.longitude;
    for (final p in points.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    if ((maxLat - minLat).abs() < 1e-6 && (maxLon - minLon).abs() < 1e-6) {
      move(points.first, zoom: 15);
      return;
    }
    final pad = math.max(
      0.0,
      math.min(
        math.min(padding.left, padding.right),
        math.min(padding.top, padding.bottom),
      ),
    );
    _gmf?.moveCamera(
      gmf.CameraUpdate.newLatLngBounds(
        gmf.LatLngBounds(
          southwest: gmf.LatLng(minLat, minLon),
          northeast: gmf.LatLng(maxLat, maxLon),
        ),
        pad,
      ),
    );
  }

  @override
  void zoomBy(double delta) {
    _zoom = (_zoom + delta).clamp(2.0, 21.0);
    _gmf?.moveCamera(gmf.CameraUpdate.zoomBy(delta));
  }

  void _onMapCreated(gmf.GoogleMapController gmfController) {
    _gmf = gmfController;
    widget.controller.attach(this);
    if (widget.config.initialBounds case final bounds?
        when bounds.length >= 2) {
      fitBounds(bounds, padding: widget.config.initialBoundsPadding);
    }
    widget.config.onMapReady?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = widget.config.mapStyle ??
        (isDark ? waddifyDarkMapStyle : waddifyLightMapStyle);

    final markers = {
      for (final m in widget.config.markers)
        gmf.Marker(
          markerId: gmf.MarkerId(m.id),
          position: _toGmf(m.position),
          anchor: m.anchor,
          consumeTapEvents: m.onTap != null,
          onTap: m.onTap,
          icon: _iconCache.resolve(
            m.icon,
            c,
            onReady: () {
              if (mounted) setState(() {});
            },
          ),
        ),
    };

    final polylines = {
      for (final p in widget.config.polylines)
        gmf.Polyline(
          polylineId: gmf.PolylineId(p.id),
          points: [for (final pt in p.points) _toGmf(pt)],
          color: p.color,
          width: p.width.round().clamp(1, 20),
        ),
    };

    return gmf.GoogleMap(
      initialCameraPosition: gmf.CameraPosition(
        target: _toGmf(widget.config.initialCenter),
        zoom: widget.config.initialZoom,
      ),
      style: style,
      padding: widget.config.padding,
      compassEnabled: false,
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled:
          widget.config.interactive && widget.config.rotateEnabled,
      scrollGesturesEnabled: widget.config.interactive,
      zoomGesturesEnabled: widget.config.interactive,
      markers: markers,
      polylines: polylines,
      onMapCreated: _onMapCreated,
      onCameraMoveStarted: widget.config.onCameraMoveStarted,
      onCameraMove: (pos) {
        _center = AppLatLng(pos.target.latitude, pos.target.longitude);
        _zoom = pos.zoom;
        widget.config.onCameraMove?.call(_center);
      },
      onCameraIdle: () => widget.config.onCameraIdle?.call(_center),
      onTap: widget.config.onTap == null
          ? null
          : (pos) =>
              widget.config.onTap!(AppLatLng(pos.latitude, pos.longitude)),
    );
  }
}
