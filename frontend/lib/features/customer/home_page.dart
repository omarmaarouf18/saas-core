import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/job_rules.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../providers/marketplace_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import 'customer_format.dart';
import 'customer_jobs_controller.dart';
import 'customer_location.dart';
import 'customer_nav.dart';
import 'market_page.dart';
import 'picker_page.dart';

/// Customer home (A-Home): pickup location, the three services, and the
/// newest ongoing order, which opens its detail directly.
class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  PickedPlace? _pickup;
  bool _locating = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final result = await CustomerLocatorScope.of(context).locate();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _pickup ??= result.place;
    });
  }

  Future<void> _changePickup() async {
    final picked = await CustomerPickerPage.open(context,
        title: context.l10n.custPickupPlace, initial: _pickup);
    if (picked != null && mounted) setState(() => _pickup = picked);
  }

  /// One navigation at a time: a double tap must not push two pages.
  Future<void> _guarded(Future<void> Function() go) async {
    if (_navigating) return;
    _navigating = true;
    try {
      await go();
    } finally {
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final jobsCtl = context.watch<CustomerJobsController>();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: jobsCtl.refresh,
        child: ListView(
          key: const Key('cust_home_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x6, QdSpace.gutter, QdSpace.x5),
          children: [
            _header(context),
            const SizedBox(height: QdSpace.x5),
            Semantics(
              header: true,
              child: Text(l10n.custHomeTitle,
                  style: QdText.screenTitle.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(height: QdSpace.x6),
            Semantics(
              container: true,
              explicitChildNodes: true,
              label: l10n.custServicesSection,
              child: Column(
                children: [
                  _CategoryCard(
                    key: const Key('cust_home_cat_delivery'),
                    icon: categoryIcon('delivery'),
                    primary: true,
                    title: l10n.custCatDelivery,
                    subtitle: l10n.custCatDeliverySub,
                    onTap: () => _openMarket('delivery'),
                  ),
                  const SizedBox(height: QdSpace.x3),
                  _CategoryCard(
                    key: const Key('cust_home_cat_shipping'),
                    icon: categoryIcon('shipping'),
                    title: l10n.custCatShipping,
                    subtitle: l10n.custCatShippingSub,
                    onTap: () => _openMarket('shipping'),
                  ),
                  const SizedBox(height: QdSpace.x3),
                  _CategoryCard(
                    key: const Key('cust_home_cat_transport'),
                    icon: categoryIcon('transport'),
                    title: l10n.custCatRide,
                    subtitle: l10n.custCatRideSub,
                    onTap: () => _openMarket('transport'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: QdSpace.x6),
            Semantics(
              header: true,
              child: Text(
                l10n.custOngoingOrder,
                style: QdText.rowTitleSm.copyWith(color: c.textSecondary),
              ),
            ),
            const SizedBox(height: 10),
            _ongoing(context, jobsCtl),
          ],
        ),
      ),
    );
  }

  void _openMarket(String category) => _guarded(() =>
      CustomerMarketPage.open(context, category: category, pickup: _pickup));

  Widget _header(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final pickup = _pickup;
    final unread = context.watch<NotificationsProvider>().unreadCount;
    final label = pickup != null
        ? placeTitle(l10n, pickup)
        : _locating
            ? l10n.custLocating
            : l10n.custChooseLocation;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: '${l10n.custPickupFrom}: $label',
            excludeSemantics: true,
            onTap: _changePickup,
            child: InkWell(
              key: const Key('cust_home_pickup'),
              onTap: _changePickup,
              borderRadius: BorderRadius.circular(QdRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: QdSize.minTouch),
                child: Row(
                  children: [
                    const QdIconTile(icon: Icons.location_on_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.custPickupFrom,
                              style: QdText.caption
                                  .copyWith(color: c.textSecondary)),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QdText.rowTitleSm
                                      .copyWith(color: c.textPrimary),
                                ),
                              ),
                              const SizedBox(width: QdSpace.x1),
                              Icon(Icons.expand_more,
                                  size: QdSize.icon, color: c.textPrimary),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: QdSpace.x3),
        QdIconButton(
          key: const Key('cust_home_bell'),
          icon: Icons.notifications_none,
          label: l10n.tooltipNotifications,
          badgeCount: unread,
          onPressed: () => _guarded(
              () => CustomerNavScope.of(context).openNotifications(context)),
        ),
      ],
    );
  }

  Widget _ongoing(BuildContext context, CustomerJobsController jobsCtl) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final marketplace = context.watch<MarketplaceProvider>();
    final job = newestOngoingJob(marketplace.customerJobs);
    if (job != null) {
      return _OngoingCard(
        key: const Key('cust_home_ongoing'),
        job: job,
        title: jobTitle(l10n, job, marketplace.services),
        onOpen: () => _guarded(() async {
          await CustomerNavScope.of(context).openOrder(context, job);
          if (mounted) await jobsCtl.refresh();
        }),
      );
    }
    if (jobsCtl.loading || !jobsCtl.loaded) {
      return const QdCard(
        key: Key('cust_home_ongoing_loading'),
        subtle: true,
        child: Center(
          child: SizedBox.square(
            dimension: QdSize.iconLg,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (jobsCtl.error != null) {
      return QdBanner(
        key: const Key('cust_home_ongoing_error'),
        tone: QdBannerTone.danger,
        icon: Icons.error_outline,
        message: l10n.custJobsLoadError,
        actionLabel: l10n.retry,
        onAction: jobsCtl.refresh,
      );
    }
    return Text(
      l10n.custNoOngoing,
      key: const Key('cust_home_no_ongoing'),
      style: QdText.body.copyWith(color: c.textSecondary),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return QdCard(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      child: ExcludeSemantics(
        child: Row(
          children: [
            QdIconTile(
              icon: icon,
              size: QdSize.iconTileLg,
              tone: primary ? QdIconTileTone.gold : QdIconTileTone.muted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: QdText.rowTitle.copyWith(color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: QdText.secondary.copyWith(color: c.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: QdSize.icon, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _OngoingCard extends StatelessWidget {
  const _OngoingCard({
    super.key,
    required this.job,
    required this.title,
    required this.onOpen,
  });

  final Job job;
  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return QdCard(
      subtle: true,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l10n.custOrderTitleRef(title, jobRefIsolated(job)),
                  style: QdText.rowTitleSm.copyWith(color: c.textPrimary),
                ),
              ),
              const SizedBox(width: QdSpace.x2),
              // Capped, not Flexible: a Flexible here would halve the title.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kChipsMaxWidth),
                child: QdJobStatusChips(
                  status: job.status,
                  cancellationRequestStatus: job.cancellationRequestStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x3),
          QdStepProgress(
            total: kJobProgressSteps,
            current: jobProgressStep(job.status),
          ),
          const SizedBox(height: QdSpace.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.custToPlace(jobPlaceLabel(l10n, job.destination)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QdText.secondary.copyWith(color: c.textSecondary),
                ),
              ),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: QdSize.buttonHeightSm),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    l10n.custTrack,
                    style: QdText.bodyStrong.copyWith(
                      color: c.textPrimary,
                      decoration: TextDecoration.underline,
                      decorationColor: c.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
