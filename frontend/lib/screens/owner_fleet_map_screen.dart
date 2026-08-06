import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/map_tracking_provider.dart';

class OwnerFleetMapScreen extends StatefulWidget {
  final String ownerId;
  final String? token;

  const OwnerFleetMapScreen({
    super.key,
    required this.ownerId,
    this.token,
  });

  @override
  State<OwnerFleetMapScreen> createState() => _OwnerFleetMapScreenState();
}

class _OwnerFleetMapScreenState extends State<OwnerFleetMapScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MapTrackingProvider>();
      if (widget.token != null) {
        provider.hydrateOwnerFleet(widget.token!);
        provider.connectAndSubscribe('fleet:${widget.ownerId}', widget.token!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fleetLiveMapTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final provider = context.read<MapTrackingProvider>();
              if (widget.token != null) {
                provider.hydrateOwnerFleet(widget.token!);
              }
            },
          ),
        ],
      ),
      body: Consumer<MapTrackingProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.markersList.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                key: Key('fleet_map_loading'),
                color: AppColors.secondary,
              ),
            );
          }

          final markers = provider.markersList;
          LatLng centerPoint =
              const LatLng(30.0444, 31.2357); // Default Cairo / center

          if (markers.isNotEmpty) {
            double avgLat = 0;
            double avgLon = 0;
            for (final m in markers) {
              avgLat += m.latitude;
              avgLon += m.longitude;
            }
            centerPoint =
                LatLng(avgLat / markers.length, avgLon / markers.length);
          }

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: centerPoint,
                  initialZoom: 12.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: mapTileUrlTemplate,
                    userAgentPackageName: mapTileUserAgent,
                    errorTileCallback: (tile, error, stackTrace) {},
                  ),
                  MarkerLayer(
                    markers: markers.map((m) {
                      return Marker(
                        width: 90.0,
                        height: 50.0,
                        point: LatLng(m.latitude, m.longitude),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.secondary),
                              ),
                              child: Text(
                                m.employeeId.length > 12
                                    ? m.employeeId.substring(0, 12)
                                    : m.employeeId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.location_on,
                              color: AppColors.secondary,
                              size: 26.0,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),

              // Empty fleet state notice
              if (markers.isEmpty && !provider.isLoading)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No active employees transmitting location.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Connection status / error banner
              if (!provider.isConnected && !provider.isLoading)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: provider.subscriptionError != null
                            ? AppColors.danger
                            : AppColors.warning,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            provider.subscriptionError != null
                                ? Icons.lock
                                : Icons.wifi_off,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              provider.subscriptionError ??
                                  'Reconnecting live tracking stream...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
