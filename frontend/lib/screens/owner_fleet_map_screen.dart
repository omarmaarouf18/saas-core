import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/constants.dart';
import '../core/provider_connection_cleanup.dart';
import '../core/theme.dart';
import '../models/employee_marker.dart';
import '../providers/map_tracking_provider.dart';
import '../widgets/themed_panel.dart';
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

class _OwnerFleetMapScreenState extends State<OwnerFleetMapScreen>
    with ProviderConnectionCleanup<OwnerFleetMapScreen> {
  final MapController _mapController = MapController();
  EmployeeMarkerData? _selectedEmployee;
  String _selectedFilter = 'all'; // 'all', 'on_route', 'idle'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MapTrackingProvider>();
      if (widget.token != null) {
        // A6: register connection teardown while context is valid — this
        // screen previously never disconnected the app-lifetime provider,
        // leaving the fleet WebSocket and its auto-reconnect timer running
        // after the map was closed.
        addConnectionTeardown(provider.disconnect);
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
          final displayedMarkers = markers.where((m) {
            if (_selectedFilter == 'on_route') {
              return m.jobId != null && m.jobId!.isNotEmpty;
            }
            if (_selectedFilter == 'idle') {
              return m.jobId == null || m.jobId!.isEmpty;
            }
            return true;
          }).toList();

          LatLng centerPoint =
              const LatLng(30.0444, 31.2357); // Default Cairo / center

          if (displayedMarkers.isNotEmpty) {
            double avgLat = 0;
            double avgLon = 0;
            for (final m in displayedMarkers) {
              avgLat += m.latitude;
              avgLon += m.longitude;
            }
            centerPoint = LatLng(avgLat / displayedMarkers.length,
                avgLon / displayedMarkers.length);
          } else if (markers.isNotEmpty) {
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
              _buildMapCanvas(centerPoint, displayedMarkers),

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
            final isOnJob = m.jobId != null && m.jobId!.isNotEmpty;
            final badgeColor =
                isOnJob ? AppColors.primary : context.semanticColors.success;
            final borderColor = isOnJob ? AppColors.secondary : Colors.white;
            final pinColor =
                isOnJob ? AppColors.secondary : context.semanticColors.success;

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
                    ThemedPanel(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(AppRadius.radiusSm),
                        border: Border.all(color: borderColor),
                        boxShadow: AppElevation.shadowLevel1List,
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.xxs,
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
                        )),
                    Icon(
                      Icons.location_on,
                      color: pinColor,
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
    final l10n = context.l10n;
    return Positioned(
      top: AppSpacing.md,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _selectedFilter = 'all'),
              child: ThemedPanel(
                  color: _selectedFilter == 'all'
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: _selectedFilter == 'all'
                      ? null
                      : Border.all(color: AppColors.outlineVariant),
                  boxShadow: AppElevation.shadowLevel1List,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.fleetFilterAllFleet,
                        style: AppTypography.labelMd.copyWith(
                          color: _selectedFilter == 'all'
                              ? AppColors.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      ThemedPanel(
                          color: _selectedFilter == 'all'
                              ? AppColors.onPrimary.withValues(alpha: 0.2)
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            "$markersCount",
                            style: AppTypography.labelSm.copyWith(
                              color: _selectedFilter == 'all'
                                  ? AppColors.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          )),
                    ],
                  )),
            ),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: () => setState(() => _selectedFilter = 'on_route'),
              child: ThemedPanel(
                  color: _selectedFilter == 'on_route'
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: _selectedFilter == 'on_route'
                      ? null
                      : Border.all(color: AppColors.outlineVariant),
                  boxShadow: AppElevation.shadowLevel1List,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemedPanel(
                          color: context.semanticColors.success,
                          shape: BoxShape.circle,
                          width: 8,
                          height: 8),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        l10n.fleetFilterOnRoute,
                        style: AppTypography.labelMd.copyWith(
                          color: _selectedFilter == 'on_route'
                              ? AppColors.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )),
            ),
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: () => setState(() => _selectedFilter = 'idle'),
              child: ThemedPanel(
                  color: _selectedFilter == 'idle'
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: _selectedFilter == 'idle'
                      ? null
                      : Border.all(color: AppColors.outlineVariant),
                  boxShadow: AppElevation.shadowLevel1List,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ThemedPanel(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                          width: 8,
                          height: 8),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        l10n.fleetFilterIdle,
                        style: AppTypography.labelMd.copyWith(
                          color: _selectedFilter == 'idle'
                              ? AppColors.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )),
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
            Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Text(
                context.l10n.noEmployeesTransmitting,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDriverCard(EmployeeMarkerData employee) {
    final isOnJob = employee.jobId != null && employee.jobId!.isNotEmpty;
    return Positioned(
      bottom: AppSpacing.xl + 64,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: ThemedCard(
        borderRadius: AppRadius.lg,
        topAccentColor:
            isOnJob ? AppColors.primary : context.semanticColors.success,
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
                    ThemedPanel(
                        color: isOnJob
                            ? AppColors.primaryContainer
                            : context.semanticColors.success
                                .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        width: 36,
                        height: 36,
                        child: Center(
                          child: Text(
                            employee.employeeId.length > 2
                                ? AppTypography.uppercaseLabel(
                                    employee.employeeId.substring(0, 2))
                                : 'DR',
                            style: AppTypography.labelMd.copyWith(
                              color: isOnJob
                                  ? AppColors.secondary
                                  : context.semanticColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.employeeId,
                          style: AppTypography.titleMd.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isOnJob)
                          Text(
                            context.l10n.assignedJobLine(employee.jobId!),
                            style: AppTypography.caption.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ThemedPanel(
                                color: context.semanticColors.success,
                                shape: BoxShape.circle,
                                width: 8,
                                height: 8,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(
                                context.l10n.fleetFilterIdle,
                                style: AppTypography.caption.copyWith(
                                  color: context.semanticColors.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  tooltip: context.l10n.tooltipClose,
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
          : ThemedWarningBanner(
              message: context.l10n.reconnectingTrackingStream,
            ),
    );
  }

  Widget _buildMapControls(LatLng centerPoint) {
    return PositionedDirectional(
      end: AppSpacing.md,
      bottom: AppSpacing.xl,
      child: Column(
        children: [
          ThemedPanel(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: AppRadius.defaultBorder,
              boxShadow: AppElevation.shadowLevel2List,
              border: Border.all(color: AppColors.outlineVariant),
              child: Column(
                children: [
                  IconButton(
                    tooltip: context.l10n.tooltipZoomIn,
                    icon: const Icon(Icons.add),
                    color: Theme.of(context).colorScheme.onSurface,
                    onPressed: _zoomIn,
                  ),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  IconButton(
                    tooltip: context.l10n.tooltipZoomOut,
                    icon: const Icon(Icons.remove),
                    color: Theme.of(context).colorScheme.onSurface,
                    onPressed: _zoomOut,
                  ),
                ],
              )),
          const SizedBox(height: AppSpacing.sm),
          ThemedPanel(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: AppElevation.shadowLevel2List,
              border: Border.all(color: AppColors.outlineVariant),
              child: IconButton(
                tooltip: context.l10n.tooltipRecenter,
                icon: const Icon(Icons.my_location),
                color: AppColors.primary,
                onPressed: () => _centerOnTarget(centerPoint),
              )),
        ],
      ),
    );
  }
}
