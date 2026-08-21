import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/employee_marker.dart';
import '../providers/map_tracking_provider.dart';
import '../widgets/app_shell.dart';
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
  EmployeeMarkerData? _selectedEmployee;

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

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _centerOnTarget(LatLng centerPoint) {
    _mapController.move(centerPoint, 13.0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppShell(
      title: l10n.fleetLiveMapTitle,
      backgroundColor: AppColors.scaffoldBackground,
      appBarBackgroundColor: AppColors.primary,
      appBarForegroundColor: AppColors.onPrimary,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.tooltipRefreshStatus,
          onPressed: () {
            final provider = context.read<MapTrackingProvider>();
            if (widget.token != null) {
              provider.hydrateOwnerFleet(widget.token!);
            }
          },
        ),
      ],
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
              // OpenStreetMap Layer
              _buildMapCanvas(centerPoint, markers),

              // Floating Fleet Filter Pills (Stitch Reference)
              _buildFleetFilterPillRow(markers.length),

              // Empty fleet state notice
              if (markers.isEmpty && !provider.isLoading)
                _buildEmptyFleetNotice(),

              // Selected Driver Detail Card (Stitch Reference)
              if (_selectedEmployee != null)
                _buildSelectedDriverCard(_selectedEmployee!),

              // Connection status / error banner
              if (!provider.isConnected && !provider.isLoading)
                _buildConnectionBanner(provider),

              // Floating Map Controls (Zoom / Recenter)
              _buildMapControls(centerPoint),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMapCanvas(LatLng centerPoint, List<EmployeeMarkerData> markers) {
    return FlutterMap(
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
              width: 100.0,
              height: 64.0,
              point: LatLng(m.latitude, m.longitude),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedEmployee = m;
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppRadius.radiusSm),
                        border: Border.all(color: AppColors.secondary),
                        boxShadow: AppElevation.shadowLevel1List,
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
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFleetFilterPillRow(int markersCount) {
    return Positioned(
      top: AppSpacing.md,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
                boxShadow: AppElevation.shadowLevel1List,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "All Fleet",
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      "$markersCount",
                      style: AppTypography.caption.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: AppColors.outlineVariant),
                boxShadow: AppElevation.shadowLevel1List,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    "On Route",
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: AppColors.outlineVariant),
                boxShadow: AppElevation.shadowLevel1List,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    "Idle",
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyFleetNotice() {
    return Positioned(
      top: 72,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: ThemedCard(
        variant: ThemedCardVariant.elevated,
        padding: AppSpacing.sm,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary),
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
    );
  }

  Widget _buildSelectedDriverCard(EmployeeMarkerData employee) {
    return Positioned(
      bottom: AppSpacing.xl + 64,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: ThemedCard(
        borderRadius: AppRadius.lg,
        topAccentColor: AppColors.primary,
        topAccentHeight: 3,
        padding: AppSpacing.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          employee.employeeId.length > 2
                              ? AppTypography.uppercaseLabel(
                                  employee.employeeId.substring(0, 2))
                              : 'DR',
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.employeeId,
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (employee.jobId != null)
                          Text(
                            "Assigned Job: #${employee.jobId}",
                            style: AppTypography.caption.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedEmployee = null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBanner(MapTrackingProvider provider) {
    return Positioned(
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
    );
  }

  Widget _buildMapControls(LatLng centerPoint) {
    return PositionedDirectional(
      end: AppSpacing.md,
      bottom: AppSpacing.xl,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.defaultBorder,
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
                const Divider(height: 1, color: AppColors.outlineVariant),
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
    );
  }
}
