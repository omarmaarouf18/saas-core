import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/provider_connection_cleanup.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/map_tracking_provider.dart';
import '../../../ui/qd_ui.dart';
import '../picker_page.dart';

/// Live courier map for the active order (A-Track top), on the existing
/// [MapTrackingProvider], as the old CustomerJobMapScreen did: hydrate from
/// `GET /users/jobs/get`, then subscribe to `job:<id>` on the chat-service
/// websocket (the provider reconnects with backoff). Shows pickup,
/// drop-off and the courier; a "waiting for the courier's location" notice
/// until a position arrives; a reconnecting notice while the socket is
/// down, or an access notice when the channel is refused. The socket is
/// torn down when the map leaves the screen.
class OrderTrackMap extends StatefulWidget {
  const OrderTrackMap({super.key, required this.job, this.height = 260});

  final Job job;
  final double height;

  @override
  State<OrderTrackMap> createState() => OrderTrackMapState();
}

class OrderTrackMapState extends State<OrderTrackMap>
    with ProviderConnectionCleanup<OrderTrackMap> {
  final MapController _map = MapController();
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MapTrackingProvider>();
      addConnectionTeardown(provider.disconnect);
      final token = context.read<AuthProvider>().token;
      if (token == null) return;
      provider.hydrateCustomerJob(widget.job.id, token);
      provider.connectAndSubscribe('job:${widget.job.id}', token);
    });
  }

  /// Re-reads the courier position (pull to refresh).
  Future<void> rehydrate() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    await context
        .read<MapTrackingProvider>()
        .hydrateCustomerJob(widget.job.id, token);
  }

  LatLng _center(MapTrackingProvider p) {
    final markers = p.markersList;
    if (markers.isNotEmpty) {
      return LatLng(markers.first.latitude, markers.first.longitude);
    }
    final pickup = p.customerJobLocation ?? widget.job.location;
    return LatLng(pickup.latitude, pickup.longitude);
  }

  void _zoom(double delta) {
    if (!_mapReady) return;
    final cam = _map.camera;
    _map.move(cam.center, cam.zoom + delta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final p = context.watch<MapTrackingProvider>();
    final pickup = p.customerJobLocation ?? widget.job.location;
    final dropoff = p.customerJobDestination ?? widget.job.destination;
    final markers = p.markersList;
    final center = _center(p);

    Marker stop(JobLocation l, {required bool isPickup}) => Marker(
          point: LatLng(l.latitude, l.longitude),
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

    final Widget? notice;
    if (p.subscriptionError != null) {
      notice = QdBanner(
        key: const Key('ord_map_denied'),
        tone: QdBannerTone.danger,
        icon: Icons.lock_outline,
        message: l10n.ordMapDenied,
      );
    } else if (!p.isConnected && !p.isLoading) {
      notice = QdBanner(
        key: const Key('ord_map_reconnecting'),
        tone: QdBannerTone.warning,
        icon: Icons.sync,
        message: l10n.ordMapReconnecting,
      );
    } else if (markers.isEmpty && !p.isLoading) {
      notice = QdBanner(
        key: const Key('ord_map_waiting'),
        tone: QdBannerTone.info,
        icon: Icons.location_searching,
        message: l10n.ordMapWaiting,
      );
    } else {
      notice = null;
    }

    return SizedBox(
      key: const Key('ord_track_map'),
      height: widget.height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              label: l10n.ordMapLabel,
              container: true,
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  onMapReady: () => _mapReady = true,
                ),
                children: [
                  TileLayer(
                    tileProvider: CustomerMapTilesScope.of(context),
                    urlTemplate: mapTileUrlTemplate,
                    userAgentPackageName: mapTileUserAgent,
                    errorTileCallback: (tile, error, stackTrace) {},
                  ),
                  MarkerLayer(markers: [
                    stop(pickup, isPickup: true),
                    if (dropoff != null) stop(dropoff, isPickup: false),
                    for (final m in markers)
                      Marker(
                        key: Key('ord_map_courier_${m.employeeId}'),
                        point: LatLng(m.latitude, m.longitude),
                        width: 36,
                        height: 36,
                        child: Container(
                          decoration: BoxDecoration(
                              color: c.navy, shape: BoxShape.circle),
                          child: Icon(Icons.two_wheeler,
                              size: 18, color: c.onNavy),
                        ),
                      ),
                  ]),
                ],
              ),
            ),
          ),
          if (p.isLoading && markers.isEmpty)
            const Positioned.fill(
              child: Center(
                key: Key('ord_map_loading'),
                child: CircularProgressIndicator(),
              ),
            ),
          if (notice != null)
            PositionedDirectional(
              top: QdSpace.x3,
              start: QdSpace.x3,
              end: QdSpace.x3,
              child: notice,
            ),
          PositionedDirectional(
            end: QdSpace.x3,
            bottom: QdSpace.x3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QdIconButton(
                  icon: Icons.add,
                  label: l10n.ordZoomIn,
                  onPressed: () => _zoom(1),
                ),
                const SizedBox(height: QdSpace.x2),
                QdIconButton(
                  icon: Icons.remove,
                  label: l10n.ordZoomOut,
                  onPressed: () => _zoom(-1),
                ),
                const SizedBox(height: QdSpace.x2),
                QdIconButton(
                  key: const Key('ord_map_recenter'),
                  icon: Icons.my_location,
                  label: l10n.ordRecenter,
                  round: true,
                  onPressed: () {
                    if (_mapReady) _map.move(center, 15);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
