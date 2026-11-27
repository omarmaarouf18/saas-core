import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/maps/app_map.dart';
import '../../../core/provider_connection_cleanup.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/map_tracking_provider.dart';
import '../../../ui/qd_ui.dart';

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
  final AppMapController _map = AppMapController();

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

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Re-reads the courier position (pull to refresh).
  Future<void> rehydrate() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    await context
        .read<MapTrackingProvider>()
        .hydrateCustomerJob(widget.job.id, token);
  }

  AppLatLng _center(MapTrackingProvider p) {
    final markers = p.markersList;
    if (markers.isNotEmpty) {
      return AppLatLng(markers.first.latitude, markers.first.longitude);
    }
    final pickup = p.customerJobLocation ?? widget.job.location;
    return AppLatLng(pickup.latitude, pickup.longitude);
  }

  void _zoom(double delta) {
    if (!_map.isReady) return;
    _map.zoomBy(delta);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.watch<MapTrackingProvider>();
    final pickup = p.customerJobLocation ?? widget.job.location;
    final dropoff = p.customerJobDestination ?? widget.job.destination;
    final markers = p.markersList;
    final center = _center(p);

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
            child: AppMap(
              controller: _map,
              semanticLabel: l10n.ordMapLabel,
              initialCenter: center,
              initialZoom: 14,
              markers: [
                AppMapMarker(
                  id: 'pickup',
                  markerKey: const Key('ord_map_pickup'),
                  position: AppLatLng(pickup.latitude, pickup.longitude),
                  icon: const AppMarkerIcon.pickupRing(),
                ),
                if (dropoff != null)
                  AppMapMarker(
                    id: 'dropoff',
                    markerKey: const Key('ord_map_dropoff'),
                    position: AppLatLng(dropoff.latitude, dropoff.longitude),
                    icon: const AppMarkerIcon.dropoffSquare(),
                  ),
                for (final m in markers)
                  AppMapMarker(
                    id: 'courier_${m.employeeId}',
                    markerKey: Key('ord_map_courier_${m.employeeId}'),
                    position: AppLatLng(m.latitude, m.longitude),
                    icon: const AppMarkerIcon.courierPin(),
                  ),
              ],
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
                    if (_map.isReady) _map.move(center, zoom: 15);
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
