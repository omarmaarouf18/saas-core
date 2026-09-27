import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../core/location_permission.dart';
import '../core/theme.dart';
import '../models/job.dart';
import '../widgets/app_shell.dart';
import '../widgets/pending_pulse_dot.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_panel.dart';

/// Employee live trip map: pickup + dropoff + the employee's OWN live
/// position on one `flutter_map` canvas.
///
/// Marker/layer composition mirrors `CustomerJobMapScreen` (`_buildMapMarkers`,
/// `_createPickupMarker`, floating zoom/recenter controls, bottom details
/// sheet) — same OSM tile stack and `AppColors` tokens, no new mechanics.
/// Two deliberate differences from the customer view:
/// 1. The third marker is the employee's on-device position via
///    `GeolocatorPlatform.getPositionStream()` — no backend round-trip
///    (unlike the customer's courier marker, which arrives over the
///    `UpdateJobLocation` broadcast).
/// 2. A dropoff marker renders from the first frame (the customer screen
///    gained its own dropoff marker in the companion fix).
class EmployeeJobMapScreen extends StatefulWidget {
  final Job job;

  /// Injectable `GeolocatorPlatform` for widget tests (mirrors
  /// `LocationPickerMap.geolocatorPlatform`).
  final GeolocatorPlatform? geolocatorPlatform;

  const EmployeeJobMapScreen({
    super.key,
    required this.job,
    this.geolocatorPlatform,
  });

  @override
  State<EmployeeJobMapScreen> createState() => _EmployeeJobMapScreenState();
}

class _EmployeeJobMapScreenState extends State<EmployeeJobMapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _selfSubscription;

  Position? _selfPosition;
  bool _isResolvingSelf = true;
  bool _selfDenied = false;
  String? _selfError;
  bool _didFitSelfOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resolveSelfPosition();
    });
  }

  @override
  void dispose() {
    _selfSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _resolveSelfPosition() async {
    setState(() {
      _isResolvingSelf = true;
      _selfDenied = false;
      _selfError = null;
    });
    try {
      final perm = await requestLocationPermission(
        platform: widget.geolocatorPlatform,
      );
      if (!mounted) return;
      if (perm != LocationPermissionResult.granted) {
        // Graceful degradation: the map still shows pickup + dropoff,
        // only the "you" marker is missing (never a crash/empty map).
        setState(() {
          _isResolvingSelf = false;
          _selfDenied = true;
        });
        return;
      }
      final geo = widget.geolocatorPlatform ?? GeolocatorPlatform.instance;
      final first = await geo.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _selfPosition = first;
        _isResolvingSelf = false;
      });
      _fitKnownPoints(includeSelfOnce: true);
      await _selfSubscription?.cancel();
      _selfSubscription = geo.getPositionStream().listen(
        (pos) {
          if (!mounted) return;
          setState(() => _selfPosition = pos);
        },
        onError: (_) {},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResolvingSelf = false;
        _selfError = friendlyErrorMessage(e);
      });
    }
  }

  /// Trip ends, shared with the declarative open-fit (`initialCameraFit`).
  List<LatLng> _tripPoints() {
    final points = <LatLng>[
      LatLng(widget.job.location.latitude, widget.job.location.longitude),
    ];
    final destination = widget.job.destination;
    if (destination != null) {
      points.add(LatLng(destination.latitude, destination.longitude));
    }
    return points;
  }

  List<LatLng> _knownPoints() {
    final points = _tripPoints();
    if (_selfPosition != null) {
      points.add(LatLng(_selfPosition!.latitude, _selfPosition!.longitude));
    }
    return points;
  }

  void _fitKnownPoints({bool includeSelfOnce = false}) {
    if (includeSelfOnce) {
      if (_didFitSelfOnce) return;
      _didFitSelfOnce = true;
    }
    final points = _knownPoints();
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15.0);
      return;
    }
    // flutter_map v7 entry point (fitBounds was removed in favor of
    // fitCamera). maxZoom guards the degenerate all-pins-on-one-spot
    // case, which would otherwise zoom to the maximum level.
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(AppSpacing.lg),
        maxZoom: 15.0,
      ),
    );
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final displayJobId = widget.job.id.length > 8
        ? AppTypography.uppercaseLabel(widget.job.id.substring(0, 8))
        : AppTypography.uppercaseLabel(widget.job.id);

    return AppShell(
      title: l10n.employeeLiveMapTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: l10n.tooltipRefreshStatus,
          onPressed: _resolveSelfPosition,
        ),
      ],
      body: Stack(
        children: [
          // 1. OpenStreetMap Interactive Canvas
          // Auto-fit runs declaratively via initialCameraFit (applied on
          // first layout, before tiles load) so open never uses a fixed
          // zoom that cuts one end off; the live fix refits once below
          // when it first arrives, and the target button refits on tap.
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                widget.job.location.latitude,
                widget.job.location.longitude,
              ),
              initialZoom: 14.0,
              // flutter_map v7 entry point (fitBounds was removed in favor
              // of fitCamera). maxZoom guards the degenerate single-point
              // case, which would otherwise zoom to the maximum level.
              initialCameraFit: CameraFit.coordinates(
                coordinates: _tripPoints(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                maxZoom: 15.0,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: mapTileUrlTemplate,
                userAgentPackageName: mapTileUserAgent,
                errorTileCallback: (tile, error, stackTrace) {},
              ),
              MarkerLayer(markers: _buildMapMarkers()),
            ],
          ),

          // 2. Self-position states: resolving pulse, denied notice,
          //    error banner with retry (never a silent empty map).
          if (_isResolvingSelf)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.marginMobile,
              right: AppSpacing.marginMobile,
              child: ThemedPanel(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: AppRadius.mdBorder,
                  boxShadow: AppElevation.shadowLevel2List,
                  border: Border.all(color: AppColors.outlineVariant),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      PendingPulseDot(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.employeeWaitingSelfPosition,
                          style: AppTypography.bodySm.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  )),
            ),
          if (!_isResolvingSelf && _selfDenied)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.marginMobile,
              right: AppSpacing.marginMobile,
              child: ThemedWarningBanner(
                key: const Key('employee_map_location_denied_banner'),
                message: l10n.employeeMapLocationDenied,
              ),
            ),
          if (!_isResolvingSelf && !_selfDenied && _selfError != null)
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.marginMobile,
              right: AppSpacing.marginMobile,
              child: ThemedErrorBanner(
                message: _selfError!,
                onRetry: _resolveSelfPosition,
              ),
            ),

          // 3. Floating Map Controls (Zoom In / Out / Fit all)
          PositionedDirectional(
            end: AppSpacing.marginMobile,
            bottom: 250.0,
            child: Column(
              children: [
                ThemedPanel(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppElevation.shadowLevel2List,
                    border: Border.all(color: AppColors.outlineVariant),
                    child: Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add),
                          color: Theme.of(context).colorScheme.onSurface,
                          tooltip: context.l10n.tooltipZoomIn,
                          onPressed: _zoomIn,
                        ),
                        const Divider(
                            height: 1, color: AppColors.outlineVariant),
                        IconButton(
                          icon: const Icon(Icons.remove),
                          color: Theme.of(context).colorScheme.onSurface,
                          tooltip: context.l10n.tooltipZoomOut,
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
                      icon: const Icon(Icons.my_location),
                      color: Theme.of(context).colorScheme.primary,
                      tooltip: context.l10n.tooltipRecenter,
                      onPressed: _fitKnownPoints,
                    )),
              ],
            ),
          ),

          // 4. Bottom Sheet Overlay (addresses + close)
          _buildBottomDetailsSheet(
            displayJobId: displayJobId,
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMapMarkers() {
    final List<Marker> mapMarkers = [
      _createPickupMarker(widget.job.location),
    ];
    final destination = widget.job.destination;
    if (destination != null) {
      mapMarkers.add(_createDropoffMarker(destination));
    }
    if (_selfPosition != null) {
      mapMarkers.add(_createSelfMarker(_selfPosition!));
    }
    return mapMarkers;
  }

  Marker _createPickupMarker(JobLocation location) {
    return Marker(
      key: const Key('employee_map_pickup_marker'),
      width: 90.0,
      height: 70.0,
      point: LatLng(location.latitude, location.longitude),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedPanel(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.onPrimary, width: 1.5),
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
          const SizedBox(height: AppSpacing.xxs),
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

  Marker _createDropoffMarker(JobLocation location) {
    return Marker(
      key: const Key('employee_map_dropoff_marker'),
      width: 90.0,
      height: 70.0,
      point: LatLng(location.latitude, location.longitude),
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
                context.l10n.mapDropoffBadge,
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.onSecondary,
                  fontWeight: FontWeight.bold,
                ),
              )),
          const SizedBox(height: AppSpacing.xxs),
          const ThemedPanel(
              color: AppColors.secondary,
              shape: BoxShape.circle,
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.location_on,
                color: AppColors.onSecondary,
                size: 18,
              )),
        ],
      ),
    );
  }

  Marker _createSelfMarker(Position position) {
    return Marker(
      key: const Key('employee_map_self_marker'),
      width: 100.0,
      height: 75.0,
      point: LatLng(position.latitude, position.longitude),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThemedPanel(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.onPrimary, width: 1.5),
              boxShadow: AppElevation.shadowLevel2List,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              child: Text(
                context.l10n.mapYouAreHereBadge,
                style: AppTypography.labelSm.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              )),
          const SizedBox(height: AppSpacing.xxs),
          ThemedPanel(
              color: AppColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.onPrimary, width: 2),
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: const Icon(
                Icons.person_pin_circle,
                color: AppColors.onPrimary,
                size: 20.0,
              )),
        ],
      ),
    );
  }

  Widget _buildBottomDetailsSheet({
    required String displayJobId,
  }) {
    final l10n = context.l10n;
    final destination = widget.job.destination;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: ThemedPanel(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.xl),
            topRight: Radius.circular(AppRadius.xl),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.scrim.withValues(alpha: 0.12),
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
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Pickup address row (Option C note-primary, coords fallback)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.trip_origin,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.pickupLocationLabel,
                            style: AppTypography.labelMd.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.job.location.addressSummary(),
                            key: const Key('employee_map_pickup_address'),
                            style: AppTypography.bodyMd.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // Dropoff address row (fallback when never set)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on,
                        size: 18, color: AppColors.secondary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.deliveryDestinationLabel,
                            style: AppTypography.labelMd.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            destination?.addressSummary() ??
                                l10n.routeDestinationNotSetYet,
                            key: const Key('employee_map_dropoff_address'),
                            style: AppTypography.bodyMd.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Close CTA
                PrimaryButton(
                  text: context.l10n.close,
                  trailingIcon: Icons.arrow_forward,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          )),
    );
  }
}
