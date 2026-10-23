import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import '../customer/picker_page.dart' show CustomerMapTilesScope;

/// Courier map: pickup (navy ring), drop-off (gold square), a straight
/// line between them and the courier's own position when known (the
/// device position the location provider already tracks; no second GPS
/// stream). Same OSM tiles as every map in the app; tests swap them via
/// [CustomerMapTilesScope]. [interactive] adds pan / zoom and a recenter
/// button (A-Courier); the offer's mini map is static (C-Offer).
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
  final MapController _map = MapController();
  bool _ready = false;

  List<LatLng> _points() => [
        LatLng(widget.job.location.latitude, widget.job.location.longitude),
        if (widget.job.destination case final d?)
          LatLng(d.latitude, d.longitude),
        if (widget.self case final s?) s,
      ];

  void _recenter() {
    if (!_ready) return;
    final pts = _points();
    if (pts.length < 2) {
      _map.move(pts.first, 15);
    } else {
      _map.fitCamera(CameraFit.coordinates(
          coordinates: pts, padding: const EdgeInsets.all(40)));
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
    final pickup = LatLng(job.location.latitude, job.location.longitude);
    final drop = job.destination == null
        ? null
        : LatLng(job.destination!.latitude, job.destination!.longitude);
    final pts = _points();

    Marker stop(LatLng p, {required bool isPickup}) => Marker(
          point: p,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: isPickup ? c.surface : c.gold,
              shape: isPickup ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isPickup ? null : BorderRadius.circular(4),
              border: Border.all(color: c.navy, width: isPickup ? 4 : 3),
            ),
          ),
        );

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: l10n.courMapLabel,
                container: true,
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: pickup,
                    initialZoom: 14,
                    initialCameraFit: pts.length < 2
                        ? null
                        : CameraFit.coordinates(
                            coordinates: pts,
                            padding: const EdgeInsets.all(32)),
                    interactionOptions: InteractionOptions(
                        flags: widget.interactive
                            ? InteractiveFlag.all & ~InteractiveFlag.rotate
                            : InteractiveFlag.none),
                    onMapReady: () => _ready = true,
                  ),
                  children: [
                    TileLayer(
                      tileProvider: CustomerMapTilesScope.of(context),
                      urlTemplate: mapTileUrlTemplate,
                      userAgentPackageName: mapTileUserAgent,
                      errorTileCallback: (tile, error, stackTrace) {},
                    ),
                    if (drop != null)
                      PolylineLayer(polylines: [
                        Polyline(
                            points: [pickup, drop],
                            strokeWidth: 4,
                            color: c.navy),
                      ]),
                    MarkerLayer(markers: [
                      stop(pickup, isPickup: true),
                      if (drop != null) stop(drop, isPickup: false),
                      if (widget.self case final s?)
                        Marker(
                          key: const Key('courier_map_self'),
                          point: s,
                          width: 28,
                          height: 28,
                          child: Container(
                            decoration: BoxDecoration(
                                color: c.navy, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: c.gold, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
            ),
            ...widget.overlays,
            if (widget.interactive)
              PositionedDirectional(
                end: QdSpace.x4,
                top: QdSpace.x4 + 52,
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
