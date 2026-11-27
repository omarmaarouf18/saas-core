import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/maps/app_map.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';

/// Courier map: pickup (navy ring), drop-off (gold square), a straight
/// line between them and the courier's own position when known (the
/// device position the location provider already tracks; no second GPS
/// stream). [interactive] adds pan / zoom and a recenter button (A-Courier);
/// the offer's mini map is static (C-Offer).
class CourierMap extends StatefulWidget {
  const CourierMap({
    super.key,
    required this.job,
    required this.height,
    this.self,
    this.interactive = false,
    this.borderRadius = 0,
    this.overlays = const [],
  });

  final Job job;
  final double height;

  /// The courier's position, when known.
  final LatLng? self;
  final bool interactive;
  final double borderRadius;

  /// Positioned children over the map (chips, buttons).
  final List<Widget> overlays;

  @override
  State<CourierMap> createState() => _CourierMapState();
}

class _CourierMapState extends State<CourierMap> {
  final AppMapController _map = AppMapController();

  List<AppLatLng> _points() => [
        AppLatLng(widget.job.location.latitude, widget.job.location.longitude),
        if (widget.job.destination case final d?)
          AppLatLng(d.latitude, d.longitude),
        if (widget.self case final s?) AppLatLng(s.latitude, s.longitude),
      ];

  void _recenter() {
    if (!_map.isReady) return;
    final pts = _points();
    if (pts.length < 2) {
      _map.move(pts.first, zoom: 15);
    } else {
      _map.fitBounds(
        pts,
        padding: const EdgeInsets.fromLTRB(40, 64, 40, 72),
      );
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final job = widget.job;
    final pickup = AppLatLng(job.location.latitude, job.location.longitude);
    final drop = job.destination == null
        ? null
        : AppLatLng(job.destination!.latitude, job.destination!.longitude);
    final self = widget.self == null
        ? null
        : AppLatLng(widget.self!.latitude, widget.self!.longitude);
    final pts = _points();

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: AppMap(
                controller: _map,
                semanticLabel: l10n.courMapLabel,
                initialCenter: pickup,
                initialZoom: 14,
                initialBounds: pts.length < 2 ? null : pts,
                // Room for the overlays (and, on the current job, the sheet
                // over the map's bottom edge).
                initialBoundsPadding: widget.interactive
                    ? const EdgeInsets.fromLTRB(40, 64, 40, 72)
                    : const EdgeInsets.all(32),
                padding: widget.interactive
                    ? const EdgeInsets.only(bottom: 24)
                    : EdgeInsets.zero,
                interactive: widget.interactive,
                rotateEnabled: false,
                polylines: [
                  if (drop != null)
                    AppMapPolyline(
                      id: 'courier_route',
                      points: [pickup, drop],
                      color: c.navy,
                      width: 4,
                    ),
                ],
                markers: [
                  AppMapMarker(
                    id: 'pickup',
                    markerKey: const Key('courier_map_pickup'),
                    position: pickup,
                    icon: const AppMarkerIcon.pickupRing(),
                  ),
                  if (drop != null)
                    AppMapMarker(
                      id: 'dropoff',
                      markerKey: const Key('courier_map_dropoff'),
                      position: drop,
                      icon: const AppMarkerIcon.dropoffSquare(),
                    ),
                  if (self != null)
                    AppMapMarker(
                      id: 'self',
                      markerKey: const Key('courier_map_self'),
                      position: self,
                      icon: const AppMarkerIcon.selfDot(),
                    ),
                ],
              ),
            ),
            ...widget.overlays,
            if (widget.interactive)
              PositionedDirectional(
                end: QdSpace.x4,
                top: QdSpace.x4,
                child: QdIconButton(
                  key: const Key('courier_map_recenter'),
                  icon: Icons.center_focus_strong_outlined,
                  label: l10n.ordRecenter,
                  round: true,
                  onPressed: _recenter,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
