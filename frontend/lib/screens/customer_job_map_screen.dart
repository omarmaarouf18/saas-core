import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../providers/map_tracking_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';

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

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _centerOnTarget(LatLng centerPoint) {
    _mapController.move(centerPoint, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayJobId = widget.jobId.length > 8
        ? widget.jobId.substring(0, 8).toUpperCase()
        : widget.jobId.toUpperCase();

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          l10n.liveCourierTracking,
          style: AppTypography.titleMd.copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.tooltipRefreshStatus,
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
              child: ThemedLoadingIndicator(
                key: Key('customer_job_map_loading'),
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

          // Add Pickup / Job location marker (Deep Navy Container with Pin Dot)
          if (provider.customerJobLocation != null) {
            mapMarkers.add(
              Marker(
                width: 90.0,
                height: 70.0,
                point: LatLng(
                  provider.customerJobLocation!.latitude,
                  provider.customerJobLocation!.longitude,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: AppRadius.smBorder,
                        border:
                            Border.all(color: AppColors.surface, width: 1.5),
                        boxShadow: AppElevation.shadowLevel2List,
                      ),
                      child: Text(
                        'Pickup',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flag,
                        color: AppColors.onPrimary,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Add Courier / Employee Marker (Amber Gold Container)
          for (final m in markers) {
            mapMarkers.add(
              Marker(
                width: 100.0,
                height: 75.0,
                point: LatLng(m.latitude, m.longitude),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: AppRadius.smBorder,
                        border:
                            Border.all(color: AppColors.primary, width: 1.5),
                        boxShadow: AppElevation.shadowLevel2List,
                      ),
                      child: Text(
                        m.employeeId.length > 12
                            ? m.employeeId.substring(0, 12)
                            : m.employeeId,
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.directions_bike,
                        color: AppColors.onSecondary,
                        size: 20.0,
                      ),
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
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: ThemedCard(
                    variant: ThemedCardVariant.elevated,
                    padding: AppSpacing.sm,
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_outlined,
                            color: AppColors.primary),
                        const SizedBox(width: AppSpacing.base),
                        Expanded(
                          child: Text(
                            'Waiting for courier location updates...',
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
                  top: markers.isEmpty ? 70.0 : AppSpacing.md,
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

              // Floating Map Controls (Zoom In / Zoom Out / My Location)
              PositionedDirectional(
                end: AppSpacing.md,
                bottom: 180.0,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadius.smBorder,
                        boxShadow: AppElevation.shadowLevel2List,
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add),
                            color: AppColors.onSurface,
                            onPressed: _zoomIn,
                          ),
                          const Divider(
                              height: 1, color: AppColors.outlineVariant),
                          IconButton(
                            icon: const Icon(Icons.remove),
                            color: AppColors.onSurface,
                            onPressed: _zoomOut,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: AppElevation.shadowLevel2List,
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.my_location),
                        color: AppColors.primary,
                        onPressed: () => _centerOnTarget(centerPoint),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Sheet Overlay (Final Fidelity)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.xl),
                      topRight: Radius.circular(AppRadius.xl),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        offset: const Offset(0, -4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 48,
                            height: 4,
                            margin:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        // Job Title & Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "#QD-$displayJobId",
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.local_shipping,
                              size: 18,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              markers.isNotEmpty
                                  ? "In Transit - Live Courier Tracking"
                                  : "Live Route Tracking Active",
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PrimaryButton(
                          text: "Back to Status",
                          trailingIcon: Icons.arrow_forward,
                          onPressed: () => Navigator.of(context).pop(),
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
