import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/map_tracking_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';

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
              child: ThemedLoadingIndicator(
                key: Key('fleet_map_loading'),
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
                        height: 60.0,
                        point: LatLng(m.latitude, m.longitude),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsetsDirectional.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.radiusSm),
                                border: Border.all(color: AppColors.secondary),
                              ),
                              child: Text(
                                m.employeeId.length > 12
                                    ? m.employeeId.substring(0, 12)
                                    : m.employeeId,
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.location_on,
                              color: AppColors.secondary,
                              size: AppIconSize.md,
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
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: ThemedCard(
                    variant: ThemedCardVariant.elevated,
                    padding: AppSpacing.sm,
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.primary),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(
                          child: Text(
                            'No active employees transmitting location.',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Connection status / error banner
              if (!provider.isConnected && !provider.isLoading)
                Positioned(
                  bottom: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: provider.subscriptionError != null
                      ? ThemedErrorBanner(
                          message: provider.subscriptionError!,
                        )
                      : const ThemedWarningBanner(
                          message: 'Reconnecting live tracking stream...',
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}
