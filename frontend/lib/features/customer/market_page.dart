import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/marketplace_service.dart';
import '../../providers/marketplace_provider.dart';
import '../../ui/qd_ui.dart';
import 'booking_page.dart';
import 'customer_format.dart';
import 'customer_location.dart';
import 'customer_theme.dart';
import 'picker_page.dart';

enum MarketSort { nearest, cheapest }

/// Search distances offered in the filter sheet, km.
const List<double> kMarketRadiiKm = [5, 10, 25, 50, 100];
const double kDefaultMarketRadiusKm = 50;

/// Orders [services] for display: open (or unknown) companies first, closed
/// ones last; inside each group nearest or cheapest first. Stable.
List<MarketplaceService> sortMarketServices(
    Iterable<MarketplaceService> services, MarketSort sort) {
  final indexed = services.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final closedA = a.value.isOpenNow == false ? 1 : 0;
    final closedB = b.value.isOpenNow == false ? 1 : 0;
    if (closedA != closedB) return closedA - closedB;
    final byKey = switch (sort) {
      MarketSort.nearest => a.value.distanceKM.compareTo(b.value.distanceKM),
      MarketSort.cheapest => a.value.finalPrice.compareTo(b.value.finalPrice),
    };
    return byKey != 0 ? byKey : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}

/// Marketplace (A-Market): companies offering [category] near the pickup,
/// with the server's estimated price, distance and open / closed state.
/// Ratings are not shown: they need one request per company today.
class CustomerMarketPage extends StatefulWidget {
  const CustomerMarketPage({super.key, this.category, this.pickup, this.now});

  /// Backend category (`delivery`, `transport`, `shipping`); null = all.
  final String? category;

  /// Pickup chosen on Home; null = find the device location here.
  final PickedPlace? pickup;

  /// Clock for "opens at" (tests).
  final DateTime Function()? now;

  static Future<void> open(BuildContext context,
          {String? category, PickedPlace? pickup}) =>
      Navigator.of(context).push<void>(customerRoute(
        (_) => CustomerMarketPage(category: category, pickup: pickup),
      ));

  @override
  State<CustomerMarketPage> createState() => _CustomerMarketPageState();
}

class _CustomerMarketPageState extends State<CustomerMarketPage> {
  PickedPlace? _place;
  bool _locating = false;
  bool _locationFailed = false;
  double _radius = kDefaultMarketRadiusKm;
  MarketSort _sort = MarketSort.nearest;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _place = widget.pickup;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_place == null) await _locate();
      if (mounted) await _load();
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final result = await CustomerLocatorScope.of(context).locate();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _place = result.place;
      _locationFailed = _place == null;
      _place ??= const PickedPlace(
          latitude: kDefaultLatitude, longitude: kDefaultLongitude);
    });
  }

  Future<void> _load() async {
    final place = _place;
    if (place == null) return;
    final gen = ++_generation;
    final marketplace = context.read<MarketplaceProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    await marketplace.fetchServices(
      nearBy: true,
      lat: place.latitude,
      lon: place.longitude,
      radius: _radius,
      // The backend sorts by price for "price"; any other value keeps the
      // $nearSphere distance order.
      sortBy: _sort == MarketSort.cheapest ? 'price' : 'distance',
    );
    if (!mounted || gen != _generation) return;
    setState(() {
      _loading = false;
      _error = marketplace.error;
    });
  }

  void _setSort(MarketSort sort) {
    setState(() => _sort = sort);
    _load();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: QdColors.of(context).surface,
      barrierColor: QdColors.of(context).scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      builder: (_) => CustomerTheme(
        child: _FilterSheet(radius: _radius, place: _place),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _radius = result.radius;
      if (result.place != null && result.place != _place) {
        _place = result.place;
        _locationFailed = false;
      }
    });
    await _load();
  }

  Future<void> _pickArea() async {
    final picked = await CustomerPickerPage.open(context,
        title: context.l10n.custSearchArea, initial: _place, showNote: false);
    if (picked == null || !mounted) return;
    setState(() {
      _place = picked;
      _locationFailed = false;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final place = _place;
    final title = widget.category == null
        ? l10n.custAllServices
        : categoryLabel(l10n, widget.category);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          QdIconButton(
            key: const Key('cust_market_filters'),
            icon: Icons.tune,
            label: l10n.custFilters,
            onPressed: _locating ? null : _openFilters,
          ),
          const SizedBox(width: QdSpace.x2),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 0, QdSpace.gutter, QdSpace.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (place != null)
                  QdCard(
                    key: const Key('cust_market_area'),
                    subtle: true,
                    onTap: _openFilters,
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: QdSpace.x3, vertical: QdSpace.x3),
                    child: Row(
                      children: [
                        Icon(Icons.near_me_outlined,
                            size: QdSize.icon, color: c.textPrimary),
                        const SizedBox(width: QdSpace.x2),
                        Expanded(
                          child: Text(
                            place.isDeviceLocation
                                ? l10n.custNearYou(formatKm(_radius))
                                : l10n.custNearPlace(
                                    placeTitle(l10n, place), formatKm(_radius)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: QdText.body.copyWith(color: c.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: QdSpace.x1),
                QdChoiceChips<MarketSort>(
                  key: const Key('cust_market_sort'),
                  semanticLabel: l10n.custSortLabel,
                  selected: _sort,
                  onChanged: _setSort,
                  choices: [
                    QdChoice(
                        value: MarketSort.nearest, label: l10n.custSortNearest),
                    QdChoice(
                        value: MarketSort.cheapest,
                        label: l10n.custSortCheapest),
                  ],
                ),
                if (_locationFailed) ...[
                  const SizedBox(height: QdSpace.x2),
                  QdBanner(
                    key: const Key('cust_market_location_off'),
                    tone: QdBannerTone.info,
                    icon: Icons.location_off_outlined,
                    message: l10n.custLocationOffBanner,
                    actionLabel: l10n.custPickArea,
                    onAction: _pickArea,
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    if (_locating) {
      return Center(
        key: const Key('cust_market_locating'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: QdSpace.x3),
            Text(l10n.custLocating,
                style: QdText.body.copyWith(color: c.textSecondary)),
          ],
        ),
      );
    }
    if (_loading) {
      return const Center(
        key: Key('cust_market_loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          child:
              QdErrorState(key: const Key('cust_market_error'), onRetry: _load),
        ),
      );
    }
    final services = context.watch<MarketplaceProvider>().services;
    final category = widget.category;
    final visible = sortMarketServices(
      category == null
          ? services
          : services.where((s) => s.category == category),
      _sort,
    );
    if (visible.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: QdEmptyState(
            key: const Key('cust_market_empty'),
            icon: Icons.storefront_outlined,
            title: l10n.custNoCompaniesTitle,
            body: l10n.custNoCompaniesBody,
            actionLabel: l10n.custChangeFilters,
            onAction: _openFilters,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('cust_market_list'),
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x5),
        itemCount: visible.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: QdSpace.x3),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Text(l10n.custCompaniesCount(visible.length),
                style: QdText.secondary.copyWith(color: c.textSecondary));
          }
          final service = visible[i - 1];
          return _ServiceCard(
            key: Key('cust_market_service_${service.id}'),
            service: service,
            now: widget.now,
            onTap: () => CustomerBookingPage.open(context,
                service: service, pickup: _place!),
          );
        },
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    super.key,
    required this.service,
    required this.onTap,
    this.now,
  });

  final MarketplaceService service;
  final VoidCallback onTap;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final closed = service.isOpenNow == false;
    final reopens = service.reopensAt;
    return QdCard(
      subtle: closed,
      padding: const EdgeInsets.all(14),
      // Closed companies are listed but cannot be booked.
      onTap: closed ? null : onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              QdIconTile.initialOf(
                service.name,
                size: 52,
                tone: closed ? QdIconTileTone.disabled : QdIconTileTone.muted,
              ),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QdText.rowTitle
                          .copyWith(color: closed ? c.neutral : c.textPrimary),
                    ),
                    Text(
                      l10n.custKmAway(formatKm(service.distanceKM)),
                      style: QdText.secondary.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (service.isOpenNow != null) ...[
                const SizedBox(width: QdSpace.x2),
                QdStatusChip(
                  label: closed ? l10n.custClosed : l10n.custOpen,
                  tone: closed ? QdTone.neutral : QdTone.success,
                ),
              ],
            ],
          ),
          if (!closed) ...[
            const SizedBox(height: QdSpace.x3),
            Container(height: 1, color: c.fillMuted),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.custEstimatedPrice,
                      style: QdText.secondary.copyWith(color: c.textSecondary)),
                ),
                Text(
                  l10n.custAboutAmount(formatMoney(l10n, service.finalPrice)),
                  style: QdText.rowTitle.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ] else if (reopens != null) ...[
            const SizedBox(height: QdSpace.x3),
            Text(
              l10n.custOpensAt(formatWhen(context, reopens, now: now?.call())),
              style: QdText.secondary.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterResult {
  const _FilterResult(this.radius, this.place);

  final double radius;
  final PickedPlace? place;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.radius, required this.place});

  final double radius;
  final PickedPlace? place;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late double _radius = widget.radius;
  late PickedPlace? _place = widget.place;

  Future<void> _pickArea() async {
    final picked = await CustomerPickerPage.open(context,
        title: context.l10n.custSearchArea, initial: _place, showNote: false);
    if (picked != null && mounted) setState(() => _place = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final label = QdText.secondary
        .copyWith(color: c.textSecondary, fontWeight: FontWeight.w600);
    final radii = {...kMarketRadiiKm, _radius}.toList()..sort();
    final place = _place;
    return QdBottomSheet(
      key: const Key('cust_market_filter_sheet'),
      title: l10n.custFilters,
      primaryLabel: l10n.custShowResults,
      onPrimary: () =>
          Navigator.of(context).pop(_FilterResult(_radius, _place)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.custFilterDistance, style: label),
            QdChoiceChips<double>(
              key: const Key('cust_market_radius'),
              semanticLabel: l10n.custFilterDistance,
              selected: _radius,
              onChanged: (r) => setState(() => _radius = r),
              choices: [
                for (final r in radii)
                  QdChoice(value: r, label: l10n.custRadiusKm(formatKm(r))),
              ],
            ),
            const SizedBox(height: QdSpace.x4),
            Text(l10n.custSearchArea, style: label),
            const SizedBox(height: QdSpace.x2),
            if (place != null) ...[
              Text(placeTitle(l10n, place),
                  style: QdText.body.copyWith(color: c.textPrimary)),
              const SizedBox(height: QdSpace.x2),
            ],
            QdButton.secondary(
              key: const Key('cust_market_pick_area'),
              label: l10n.custPickArea,
              icon: Icons.map_outlined,
              onPressed: _pickArea,
            ),
          ],
        ),
      ),
    );
  }
}
