import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:frontend/core/maps/app_map.dart';
import 'package:frontend/core/maps/map_marker_renderer.dart';

/// Default [AppMapViewBuilder] for widget tests: renders markers, polylines,
/// drag-to-pan, tap, and imperative camera moves without native platform views.
Widget fakeAppMapBuilder(
  BuildContext context,
  AppMapConfig config,
  AppMapController controller,
) =>
    FakeAppMap(config: config, controller: controller);

/// Test double for the native `GoogleMap` view inside [AppMap].
class FakeAppMap extends StatefulWidget {
  const FakeAppMap({
    super.key,
    required this.config,
    required this.controller,
  });

  final AppMapConfig config;
  final AppMapController controller;

  @override
  State<FakeAppMap> createState() => FakeAppMapState();
}

class FakeAppMapState extends State<FakeAppMap> implements AppMapHandle {
  late AppLatLng _center = widget.config.initialCenter;
  late double _zoom = widget.config.initialZoom;
  Size _viewportSize = const Size(360, 260);
  bool _initialBoundsApplied = false;

  @override
  AppLatLng get center => _center;

  @override
  double get zoom => _zoom;

  @override
  void initState() {
    super.initState();
    widget.controller.attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_initialBoundsApplied &&
          widget.config.initialBounds != null &&
          widget.config.initialBounds!.isNotEmpty) {
        _initialBoundsApplied = true;
        _applyFitBounds(
          widget.config.initialBounds!,
          padding: widget.config.initialBoundsPadding,
          notifyCallbacks: false,
        );
      }
      widget.config.onMapReady?.call();
    });
  }

  @override
  void dispose() {
    widget.controller.detach(this);
    super.dispose();
  }

  @override
  void move(AppLatLng target, {double? zoom}) {
    setState(() {
      _center = target;
      if (zoom != null) _zoom = zoom;
    });
    widget.config.onCameraMove?.call(_center);
    widget.config.onCameraIdle?.call(_center);
  }

  @override
  void fitBounds(List<AppLatLng> points, {required EdgeInsets padding}) {
    _applyFitBounds(points, padding: padding, notifyCallbacks: true);
  }

  void _applyFitBounds(
    List<AppLatLng> points, {
    required EdgeInsets padding,
    required bool notifyCallbacks,
  }) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      setState(() {
        _center = points.first;
        _zoom = 15;
      });
      if (notifyCallbacks) {
        widget.config.onCameraMove?.call(_center);
        widget.config.onCameraIdle?.call(_center);
      }
      return;
    }

    var minU = double.infinity;
    var maxU = double.negativeInfinity;
    var minV = double.infinity;
    var maxV = double.negativeInfinity;
    for (final p in points) {
      final (u, v) = _toMercator(p);
      if (u < minU) minU = u;
      if (u > maxU) maxU = u;
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }

    final du = maxU - minU;
    final dv = maxV - minV;
    if (du < 1e-8 && dv < 1e-8) {
      setState(() {
        _center = points.first;
        _zoom = 15;
      });
    } else {
      final effW = math.max(16.0, _viewportSize.width - padding.horizontal);
      final effH = math.max(16.0, _viewportSize.height - padding.vertical);
      final zx = du > 0 ? math.log(effW / (256.0 * du)) / math.ln2 : 18.0;
      final zy = dv > 0 ? math.log(effH / (256.0 * dv)) / math.ln2 : 18.0;
      final nextZoom = math.min(zx, zy).clamp(2.0, 18.0);
      final scale = 256.0 * math.pow(2.0, nextZoom);
      final shiftU = (padding.right - padding.left) / (2.0 * scale);
      final shiftV = (padding.bottom - padding.top) / (2.0 * scale);
      final midU = (minU + maxU) / 2.0 + shiftU;
      final midV = (minV + maxV) / 2.0 + shiftV;
      setState(() {
        _zoom = nextZoom;
        _center = _fromMercator(midU, midV);
      });
    }

    if (notifyCallbacks) {
      widget.config.onCameraMove?.call(_center);
      widget.config.onCameraIdle?.call(_center);
    }
  }

  @override
  void zoomBy(double delta) {
    setState(() {
      _zoom = (_zoom + delta).clamp(2.0, 21.0);
    });
    widget.config.onCameraMove?.call(_center);
    widget.config.onCameraIdle?.call(_center);
  }

  static (double, double) _toMercator(AppLatLng p) {
    final lat = p.latitude.clamp(-85.05112878, 85.05112878);
    final rad = lat * math.pi / 180.0;
    final u = (p.longitude + 180.0) / 360.0;
    final v =
        (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0;
    return (u, v);
  }

  static AppLatLng _fromMercator(double u, double v) {
    final lon = (u * 360.0 - 180.0).clamp(-180.0, 180.0);
    final n = math.pi * (1.0 - 2.0 * v);
    final latRad = math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    final lat = (latRad * 180.0 / math.pi).clamp(-85.05112878, 85.05112878);
    return AppLatLng(lat, lon);
  }

  Offset _project(AppLatLng p, Size size) {
    final scale = 256.0 * math.pow(2.0, _zoom);
    final (cu, cv) = _toMercator(_center);
    final (pu, pv) = _toMercator(p);
    return Offset(
      size.width / 2.0 + (pu - cu) * scale,
      size.height / 2.0 + (pv - cv) * scale,
    );
  }

  AppLatLng _unproject(Offset px, Size size) {
    final scale = 256.0 * math.pow(2.0, _zoom);
    final (cu, cv) = _toMercator(_center);
    return _fromMercator(
      cu + (px.dx - size.width / 2.0) / scale,
      cv + (px.dy - size.height / 2.0) / scale,
    );
  }

  void _handlePanStart(DragStartDetails details) {
    widget.config.onCameraMoveStarted?.call();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final scale = 256.0 * math.pow(2.0, _zoom);
    final (cu, cv) = _toMercator(_center);
    final next = _fromMercator(
      cu - details.delta.dx / scale,
      cv - details.delta.dy / scale,
    );
    setState(() => _center = next);
    widget.config.onCameraMove?.call(_center);
  }

  void _handlePanEnd(DragEndDetails details) {
    widget.config.onCameraIdle?.call(_center);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 260,
        );
        _viewportSize = size;
        if (!_initialBoundsApplied &&
            widget.config.initialBounds != null &&
            widget.config.initialBounds!.length >= 2) {
          _initialBoundsApplied = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _applyFitBounds(
              widget.config.initialBounds!,
              padding: widget.config.initialBoundsPadding,
              notifyCallbacks: false,
            );
          });
        }

        final stack = ColoredBox(
          color: const Color(0xFFE0E0E0),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (widget.config.polylines.isNotEmpty)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PolylinePainter(
                      polylines: widget.config.polylines,
                      project: (p) => _project(p, size),
                    ),
                  ),
                ),
              for (final m in widget.config.markers)
                _buildMarker(context, m, size),
            ],
          ),
        );

        if (!widget.config.interactive) return stack;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.config.onTap == null
              ? null
              : (d) => widget.config.onTap!(_unproject(d.localPosition, size)),
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: stack,
        );
      },
    );
  }

  Widget _buildMarker(BuildContext context, AppMapMarker m, Size size) {
    final pt = _project(m.position, size);
    final w = m.icon.size.width;
    final h = m.icon.size.height;
    Widget child = buildAppMarkerWidget(context, m.icon);
    if (m.onTap != null) {
      child = GestureDetector(onTap: m.onTap, child: child);
    }
    if (m.semanticLabel != null) {
      child = Semantics(
        button: m.onTap != null,
        selected: m.selected,
        label: m.semanticLabel,
        excludeSemantics: true,
        onTap: m.onTap,
        child: child,
      );
    }
    return Positioned(
      key: m.markerKey,
      left: pt.dx - w * m.anchor.dx,
      top: pt.dy - h * m.anchor.dy,
      width: w,
      height: h,
      child: child,
    );
  }
}

class _PolylinePainter extends CustomPainter {
  const _PolylinePainter({required this.polylines, required this.project});

  final List<AppMapPolyline> polylines;
  final Offset Function(AppLatLng) project;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in polylines) {
      if (line.points.length < 2) continue;
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      final first = project(line.points.first);
      path.moveTo(first.dx, first.dy);
      for (final p in line.points.skip(1)) {
        final pt = project(p);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PolylinePainter oldDelegate) => true;
}
