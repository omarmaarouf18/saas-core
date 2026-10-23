import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/provider_connection_cleanup.dart';
import '../../l10n/l10n.dart';
import '../../models/employee_marker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/map_tracking_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/customer_location.dart';
import '../customer/picker_page.dart';
import 'employee_page.dart';
import 'order_detail_page.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_rules.dart';

/// Team map (O-Fleet): every courier sharing a location, all / on a job /
/// free, and a sheet for the selected courier with their order and page.
///
/// Behaviour kept from OwnerFleetMapScreen, on the same
/// [MapTrackingProvider]: hydrate from `GET /users/employees/available` +
/// `GET /users/jobs/owner`, subscribe to `fleet:<ownerId>` on the
/// chat-service websocket (the provider reconnects with backoff), roster
/// names for the markers, a reconnecting notice while the socket is down,
/// an access notice when the channel is refused, a load error with retry,
/// "nobody is sharing a location", zoom and recentre, and the socket torn
/// down when the page closes. Changed: provider error text is never shown
/// raw; a marker whose known job is finished counts as free.
class OwnerFleetMapPage extends StatefulWidget {
  const OwnerFleetMapPage({super.key, this.focusEmployeeId});

  /// Courier selected when the page opens (from their page or an order).
  final String? focusEmployeeId;

  @override
  State<OwnerFleetMapPage> createState() => _OwnerFleetMapPageState();
}

class _OwnerFleetMapPageState extends State<OwnerFleetMapPage>
    with ProviderConnectionCleanup<OwnerFleetMapPage> {
  final MapController _map = MapController();
  bool _mapReady = false;
  FleetFilter _filter = FleetFilter.all;
  String? _selectedId;
  Map<String, String> _appliedNames = const {};

  @override
  void initState() {
    super.initState();
    _selectedId = widget.focusEmployeeId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MapTrackingProvider>();
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) return;
      addConnectionTeardown(provider.disconnect);
      provider.hydrateOwnerFleet(token);
      provider.connectAndSubscribe('fleet:${auth.user?.id ?? ''}', token);
      // Names need the roster: load it when the shell has not yet.
      final data = context.read<OwnerDataController>();
      if (data.employees.isEmpty) data.refreshEmployees();
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _rehydrate() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    await context.read<MapTrackingProvider>().hydrateOwnerFleet(token);
  }

  /// Applies the roster names after the frame: the provider notifies, which
  /// is not allowed during build. A no-op when unchanged.
  void _syncNames(MapTrackingProvider provider, OwnerDataController data) {
    final names = <String, String>{
      for (final e in data.employees)
        if (e.id.isNotEmpty && e.displayName.isNotEmpty) e.id: e.displayName,
    };
    if (mapEquals(names, _appliedNames)) return;
    _appliedNames = names;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) provider.setEmployeeNameLookup(names);
    });
  }

  String _name(EmployeeMarkerData m) {
    final n = m.employeeName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return context.l10n.ownCourierUnknown(shortIdIsolated(m.employeeId));
  }

  LatLng _centerOf(List<EmployeeMarkerData> markers) {
    if (markers.isEmpty) {
      return const LatLng(kDefaultLatitude, kDefaultLongitude);
    }
    var lat = 0.0, lon = 0.0;
    for (final m in markers) {
      lat += m.latitude;
      lon += m.longitude;
    }
    return LatLng(lat / markers.length, lon / markers.length);
  }

  void _zoom(double delta) {
    if (!_mapReady) return;
    final cam = _map.camera;
    _map.move(cam.center, cam.zoom + delta);
  }

  void _select(EmployeeMarkerData m) {
    setState(() => _selectedId = m.employeeId);
    if (_mapReady) {
      _map.move(LatLng(m.latitude, m.longitude), _map.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final provider = context.watch<MapTrackingProvider>();
    final data = context.watch<OwnerDataController>();
    _syncNames(provider, data);

    final all = provider.markersList;
    final jobOf = {
      for (final m in all) m.employeeId: fleetJobIdOf(m.jobId, data.jobs)
    };
    final shown = all
        .where((m) => fleetFilterMatches(_filter, jobOf[m.employeeId]))
        .toList();
    final selected = all.where((m) => m.employeeId == _selectedId).firstOrNull;
    final center = selected != null
        ? LatLng(selected.latitude, selected.longitude)
        : _centerOf(shown.isNotEmpty ? shown : all);

    final Widget? notice;
    if (provider.subscriptionError != null) {
      notice = QdBanner(
        key: const Key('own_fleet_denied'),
        tone: QdBannerTone.danger,
        icon: Icons.lock_outline,
        message: l10n.ownFleetDenied,
      );
    } else if (provider.error != null && all.isEmpty && !provider.isLoading) {
      notice = QdBanner(
        key: const Key('own_fleet_error'),
        tone: QdBannerTone.danger,
        icon: Icons.error_outline,
        message: l10n.ownFleetLoadError,
        actionLabel: l10n.retry,
        onAction: _rehydrate,
      );
    } else if (!provider.isConnected && !provider.isLoading) {
      notice = QdBanner(
        key: const Key('own_fleet_reconnecting'),
        tone: QdBannerTone.warning,
        icon: Icons.sync,
        message: l10n.ownFleetReconnecting,
      );
    } else if (all.isEmpty && !provider.isLoading) {
      notice = QdBanner(
        key: const Key('own_fleet_empty'),
        tone: QdBannerTone.info,
        icon: Icons.location_searching,
        message: l10n.ownFleetNobody,
        actionLabel: l10n.ownFleetRefresh,
        onAction: _rehydrate,
      );
    } else {
      notice = null;
    }

    return Scaffold(
      key: const Key('own_fleet_page'),
      backgroundColor: c.fillMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: l10n.ownFleetMapLabel,
                    container: true,
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 13,
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
                          for (final m in shown)
                            _marker(context, m,
                                onJob: jobOf[m.employeeId] != null,
                                selected: m.employeeId == _selectedId),
                        ]),
                      ],
                    ),
                  ),
                ),
                if (provider.isLoading && all.isEmpty)
                  const Positioned.fill(
                    child: Center(
                      key: Key('own_fleet_loading'),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (provider.isLoading && all.isNotEmpty)
                  const PositionedDirectional(
                    top: 0,
                    start: 0,
                    end: 0,
                    child: LinearProgressIndicator(
                        key: Key('own_fleet_revalidating'), minHeight: 3),
                  ),
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  end: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          QdSpace.x3, QdSpace.x3, QdSpace.x3, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              QdIconButton(
                                key: const Key('own_fleet_back'),
                                icon: Icons.arrow_back,
                                label: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                round: true,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: QdSpace.x2),
                              Flexible(
                                child: _FleetFilterBar(
                                  selected: _filter,
                                  onChanged: (f) => setState(() => _filter = f),
                                ),
                              ),
                            ],
                          ),
                          if (notice != null) ...[
                            const SizedBox(height: QdSpace.x2),
                            notice,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const PositionedDirectional(
                  start: QdSpace.x3,
                  bottom: QdSpace.x4,
                  child: _Legend(),
                ),
                PositionedDirectional(
                  end: QdSpace.x3,
                  bottom: QdSpace.x4,
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
                        key: const Key('own_fleet_recenter'),
                        icon: Icons.my_location,
                        label: l10n.ordRecenter,
                        round: true,
                        onPressed: () {
                          if (_mapReady) _map.move(center, 13);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          QdDockedPanel(
            child: selected == null
                ? _Summary(
                    total: all.length,
                    onJob: jobOf.values.where((j) => j != null).length,
                  )
                : _CourierSheet(
                    key: Key('own_fleet_sheet_${selected.employeeId}'),
                    marker: selected,
                    name: _name(selected),
                    jobId: jobOf[selected.employeeId],
                    onClose: () => setState(() => _selectedId = null),
                  ),
          ),
        ],
      ),
    );
  }

  Marker _marker(BuildContext context, EmployeeMarkerData m,
      {required bool onJob, required bool selected}) {
    final c = QdColors.of(context);
    final size = selected ? 44.0 : 36.0;
    final name = _name(m);
    return Marker(
      key: Key('own_fleet_marker_${m.employeeId}'),
      point: LatLng(m.latitude, m.longitude),
      width: size,
      height: size,
      child: Semantics(
        button: true,
        selected: selected,
        label:
            '$name, ${onJob ? context.l10n.ownStateOnJob : context.l10n.ownStateFree}',
        excludeSemantics: true,
        onTap: () => _select(m),
        child: GestureDetector(
          onTap: () => _select(m),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onJob ? c.navy : c.surface,
              shape: BoxShape.circle,
              border: Border.all(
                  color: onJob ? c.gold : c.navy, width: selected ? 4 : 3),
            ),
            child: Text(
              QdAvatarInitial.initialOf(name),
              style: QdText.chip.copyWith(
                  color: onJob ? c.onNavy : c.navy,
                  fontSize: selected ? 15 : 13,
                  height: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

/// All / on a job / free pills in one white pill (O-Fleet header).
class _FleetFilterBar extends StatelessWidget {
  const _FleetFilterBar({required this.selected, required this.onChanged});

  final FleetFilter selected;
  final ValueChanged<FleetFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    Widget pill(FleetFilter f, String label) {
      final on = f == selected;
      return Semantics(
        button: true,
        selected: on,
        inMutuallyExclusiveGroup: true,
        label: label,
        excludeSemantics: true,
        onTap: on ? null : () => onChanged(f),
        child: Material(
          key: Key('own_fleet_filter_${f.name}'),
          color: on ? c.navy : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: on ? null : () => onChanged(f),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: QdSpace.x3),
                child: Center(
                  widthFactor: 1,
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: QdText.secondary.copyWith(
                          color: on ? c.surface : c.textPrimary,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: l10n.ownFleetFilterLabel,
      explicitChildNodes: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          padding: const EdgeInsets.all(QdSpace.x1),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(QdRadius.pill),
            border: Border.all(color: c.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                pill(FleetFilter.all, l10n.ownFleetAll),
                const SizedBox(width: 6),
                pill(FleetFilter.onJob, l10n.ownStateOnJob),
                const SizedBox(width: 6),
                pill(FleetFilter.free, l10n.ownFleetFree),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    Widget row(Color fill, Color ring, double ringWidth, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: ringWidth),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: QdText.caption.copyWith(color: c.textPrimary)),
          ],
        );
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: QdSpace.x3, vertical: QdSpace.x2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(QdRadius.sm),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            row(c.navy, c.gold, 3, l10n.ownStateOnJob),
            const SizedBox(height: 6),
            row(c.surface, c.navy, 2, l10n.ownStateFree),
          ],
        ),
      ),
    );
  }
}

/// The panel when nobody is selected: how many couriers are on the map.
class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.onJob});

  final int total;
  final int onJob;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Column(
      key: const Key('own_fleet_summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.ownFleetSummary(total, onJob),
            style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
        const SizedBox(height: 2),
        Text(total == 0 ? l10n.ownFleetSummaryNone : l10n.ownFleetTapHint,
            style: QdText.caption.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

/// The selected courier (O-Fleet sheet): name, last update, state, their
/// order and their page.
class _CourierSheet extends StatelessWidget {
  const _CourierSheet({
    super.key,
    required this.marker,
    required this.name,
    required this.jobId,
    required this.onClose,
  });

  final EmployeeMarkerData marker;
  final String name;
  final String? jobId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final job = jobId == null ? null : data.jobById(jobId!);
    final inRoster = data.employeeById(marker.employeeId) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            QdAvatarInitial(name: name, size: 44),
            const SizedBox(width: QdSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QdText.rowTitle.copyWith(color: c.textPrimary)),
                  Text(
                    l10n.ownFleetLastUpdate(
                        formatAgo(context, marker.updatedAt, now: data.now())),
                    style: QdText.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: QdSpace.x2),
            jobId != null
                ? QdStatusChip(label: l10n.ownStateOnJob, tone: QdTone.warning)
                : QdStatusChip(label: l10n.ownStateFree, tone: QdTone.success),
            QdIconButton(
              key: const Key('own_fleet_sheet_close'),
              icon: Icons.close,
              label: l10n.ownFleetClose,
              onPressed: onClose,
            ),
          ],
        ),
        if (jobId != null) ...[
          const SizedBox(height: QdSpace.x3),
          Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QdRadius.sm),
              side: BorderSide(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const Key('own_fleet_sheet_order'),
              onTap: () => OwnerOrderDetailPage.open(context, jobId!),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: QdSize.minTouch),
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          job == null
                              ? l10n.ownFleetOrderRef(
                                  '\u2066#QD-${_shortRef(jobId!)}\u2069')
                              : l10n.ownFleetOrderTo(
                                  jobRefIsolated(job),
                                  jobPlaceLabel(
                                      l10n, job.destination ?? job.location)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: QdText.body.copyWith(color: c.textPrimary),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: QdSize.icon, color: c.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        if (inRoster) ...[
          const SizedBox(height: QdSpace.x2),
          QdButton.secondary(
            key: const Key('own_fleet_sheet_courier'),
            label: l10n.ownFleetCourierPage,
            small: true,
            fullWidth: true,
            onPressed: () => OwnerEmployeePage.open(context, marker.employeeId),
          ),
        ],
      ],
    );
  }

  static String _shortRef(String id) =>
      (id.length > 8 ? id.substring(0, 8) : id).toUpperCase();
}
