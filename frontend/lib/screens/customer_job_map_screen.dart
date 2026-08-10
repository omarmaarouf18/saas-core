import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/map_tracking_provider.dart';

class CustomerJobMapScreen extends StatefulWidget {
  final String jobId;
  final String token;

  const CustomerJobMapScreen({
    super.key,
    required this.jobId,
    required this.token,
  });

  @override
  State<CustomerJobMapScreen> createState() => _CustomerJobMapScreenState();
}

class _CustomerJobMapScreenState extends State<CustomerJobMapScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MapTrackingProvider>();
      provider.hydrateCustomerJob(widget.jobId, widget.token);
      provider.connectAndSubscribe('job:${widget.jobId}', widget.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.liveCourierTracking),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final provider = context.read<MapTrackingProvider>();
              provider.hydrateCustomerJob(widget.jobId, widget.token);
            },
          ),
        ],
      ),
      body: Consumer<MapTrackingProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.markersList.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(
                key: Key('customer_job_map_loading'),
                color: AppColors.secondary,
              ),
            );
          }

          final markers = provider.markersList;

          LatLng centerPoint = const LatLng(30.0444, 31.2357); // Default Cairo
          if (markers.isNotEmpty) {
            final m = markers.first;
            centerPoint = LatLng(m.latitude, m.longitude);
          } else if (provider.customerJobLocation != null) {
            centerPoint = LatLng(
              provider.customerJobLocation!.latitude,
              provider.customerJobLocation!.longitude,
            );
          }

          final List<Marker> mapMarkers = [];

          // Add Pickup / Job location marker
          if (provider.customerJobLocation != null) {
            mapMarkers.add(
              Marker(
                width: 70.0,
                height: 45.0,
                point: LatLng(
                  provider.customerJobLocation!.latitude,
                  provider.customerJobLocation!.longitude,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.radiusSm),
                      ),
                      child: const Text(
                        'Pickup',
                        style: TextStyle(
                          color: AppColors.onPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.flag,
                      color: AppColors.primary,
                      size: 24.0,
                    ),
                  ],
                ),
              ),
            );
          }

          // Add Courier / Employee Marker
          for (final m in markers) {
            mapMarkers.add(
              Marker(
                width: 90.0,
                height: 50.0,
                point: LatLng(m.latitude, m.longitude),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 6, vertical: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.radiusSm),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Text(
                        m.employeeId.length > 12
                            ? m.employeeId.substring(0, 12)
                            : m.employeeId,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.directions_bike,
                      color: AppColors.primary,
                      size: 26.0,
                    ),
                  ],
                ),
              ),
            );
          }

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: centerPoint,
                  initialZoom: 14.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: mapTileUrlTemplate,
                    userAgentPackageName: mapTileUserAgent,
                    errorTileCallback: (tile, error, stackTrace) {},
                  ),
                  MarkerLayer(markers: mapMarkers),
                ],
              ),

              // Empty courier position notice
              if (markers.isEmpty && !provider.isLoading)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Material(
                    elevation: 4,
                    borderRadius:
                        BorderRadius.circular(AppRadius.radiusDefault),
                    child: Container(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppRadius.radiusDefault),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_car_outlined,
                              color: AppColors.primary),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: Text(
                              'Waiting for courier location updates...',
                              style:
                                  AppTypography.labelLg.copyWith(fontSize: 13),
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
                    borderRadius:
                        BorderRadius.circular(AppRadius.radiusDefault),
                    child: Container(
                      padding:
                          const EdgeInsetsDirectional.all(AppSpacing.baseSm),
                      decoration: BoxDecoration(
                        color: provider.subscriptionError != null
                            ? AppColors.danger
                            : AppColors.warning,
                        borderRadius:
                            BorderRadius.circular(AppRadius.radiusDefault),
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
                          const SizedBox(width: AppSpacing.base),
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
