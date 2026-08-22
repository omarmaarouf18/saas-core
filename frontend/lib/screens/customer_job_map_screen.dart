import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/employee_marker.dart';
import '../models/job.dart';
import '../providers/map_tracking_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/app_shell.dart';
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
        ? AppTypography.uppercaseLabel(widget.jobId.substring(0, 8))
        : AppTypography.uppercaseLabel(widget.jobId);

    return AppShell(
      title: l10n.liveCourierTracking,
      backgroundColor: AppColors.background,
      appBarBackgroundColor: AppColors.primary,
      appBarForegroundColor: AppColors.onPrimary,
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
          final centerPoint = _computeCenterPoint(provider, markers);
          final mapMarkers = _buildMapMarkers(provider, markers);

          return Stack(
            children: [
              // 1. OpenStreetMap Interactive Canvas
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

              // 2. Waiting for Courier Location Notice
              if (markers.isEmpty && !provider.isLoading) _buildWaitingNotice(),

              // 3. Reconnecting / Subscription Error Banner
              if (!provider.isConnected && !provider.isLoading)
                _buildConnectionStatusBanner(provider, markers.isEmpty),

              // 4. Floating Map Controls (Zoom In / Out / My Location)
              _buildFloatingControls(centerPoint),

              // 5. Bottom Sheet Overlay (Final Fidelity Stitch Layout)
              _buildBottomDetailsSheet(
                displayJobId: displayJobId,
                hasActiveMarkers: markers.isNotEmpty,
              ),
            ],
          );
        },
      ),
    );
  }

  LatLng _computeCenterPoint(
    MapTrackingProvider provider,
    List<EmployeeMarkerData> markers,
  ) {
    if (markers.isNotEmpty) {
      final m = markers.first;
      return LatLng(m.latitude, m.longitude);
    }
    if (provider.customerJobLocation != null) {
      return LatLng(
        provider.customerJobLocation!.latitude,
        provider.customerJobLocation!.longitude,
      );
    }
    return const LatLng(30.0444, 31.2357); // Cairo default
  }

  List<Marker> _buildMapMarkers(
    MapTrackingProvider provider,
    List<EmployeeMarkerData> markers,
  ) {
    final List<Marker> mapMarkers = [];

    // Pickup Marker
    if (provider.customerJobLocation != null) {
      mapMarkers.add(
        _createPickupMarker(provider.customerJobLocation!),
      );
    }

    // Active Courier Markers
    for (final m in markers) {
      mapMarkers.add(
        _createCourierMarker(m),
      );
    }

    return mapMarkers;
  }

  Marker _createPickupMarker(JobLocation location) {
    return Marker(
      width: 90.0,
      height: 70.0,
      point: LatLng(location.latitude, location.longitude),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedPanel(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.surface, width: 1.5),
              boxShadow: AppElevation.shadowLevel2List,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              child: Text(
                context.l10n.mapPickupBadge,
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              )),
          const SizedBox(height: 2),
          const ThemedPanel(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.flag,
                color: AppColors.onPrimary,
                size: 18,
              )),
        ],
      ),
    );
  }

  Marker _createCourierMarker(EmployeeMarkerData markerData) {
    final displayName = markerData.employeeId.length > 12
        ? markerData.employeeId.substring(0, 12)
        : markerData.employeeId;

    return Marker(
      width: 100.0,
      height: 75.0,
      point: LatLng(markerData.latitude, markerData.longitude),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedPanel(
              color: AppColors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.primary, width: 1.5),
              boxShadow: AppElevation.shadowLevel2List,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              child: Text(
                displayName,
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.onSecondary,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              )),
          const SizedBox(height: 2),
          ThemedPanel(
              color: AppColors.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: const Icon(
                Icons.directions_bike,
                color: AppColors.onSecondary,
                size: 20.0,
              )),
        ],
      ),
    );
  }

  Widget _buildWaitingNotice() {
    return Positioned(
      top: AppSpacing.md,
      left: AppSpacing.marginMobile,
      right: AppSpacing.marginMobile,
      child: ThemedCard(
        variant: ThemedCardVariant.elevated,
        padding: AppSpacing.sm,
        borderRadius: AppRadius.md,
        child: Row(
          children: [
            const Icon(
              Icons.directions_car_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.waitingCourierUpdates,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatusBanner(
    MapTrackingProvider provider,
    bool isMarkersEmpty,
  ) {
    return Positioned(
      top: isMarkersEmpty ? 70.0 : AppSpacing.md,
      left: AppSpacing.marginMobile,
      right: AppSpacing.marginMobile,
      child: provider.subscriptionError != null
          ? ThemedErrorBanner(
              message: provider.subscriptionError!,
            )
          : ThemedWarningBanner(
              message: context.l10n.reconnectingTrackingStream,
            ),
    );
  }

  Widget _buildFloatingControls(LatLng centerPoint) {
    return PositionedDirectional(
      end: AppSpacing.marginMobile,
      bottom: 200.0,
      child: Column(
        children: [
          ThemedPanel(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppElevation.shadowLevel2List,
              border: Border.all(color: AppColors.outlineVariant),
              child: Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add),
                    color: AppColors.onSurface,
                    tooltip: context.l10n.tooltipZoomIn,
                    onPressed: _zoomIn,
                  ),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    color: AppColors.onSurface,
                    tooltip: context.l10n.tooltipZoomOut,
                    onPressed: _zoomOut,
                  ),
                ],
              )),
          const SizedBox(height: AppSpacing.sm),
          ThemedPanel(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: AppElevation.shadowLevel2List,
              border: Border.all(color: AppColors.outlineVariant),
              child: IconButton(
                icon: const Icon(Icons.my_location),
                color: AppColors.primary,
                tooltip: context.l10n.tooltipRecenter,
                onPressed: () => _centerOnTarget(centerPoint),
              )),
        ],
      ),
    );
  }

  Widget _buildBottomDetailsSheet({
    required String displayJobId,
    required bool hasActiveMarkers,
  }) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ThemedPanel(
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
                Center(
                  child: ThemedPanel(
                      color: AppColors.outlineVariant,
                      borderRadius: AppRadius.xsBorder,
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: AppSpacing.md)),
                ),
                // Job ID Header
                Text(
                  "#QD-$displayJobId",
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                // Live Tracking Status Subtitle
                Row(
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        hasActiveMarkers
                            ? "In Transit - Live Courier Tracking"
                            : "Live Route Tracking Active",
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Back to Status / View Details CTA
                PrimaryButton(
                  text: context.l10n.backToStatusBtn,
                  trailingIcon: Icons.arrow_forward,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          )),
    );
  }
}
