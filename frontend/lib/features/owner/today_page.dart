import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/marketplace_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import 'order_detail_page.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_rules.dart';
import 'owner_widgets.dart';
import 'recon_page.dart';
import 'team_page.dart';

/// Today (A-Owner): KYB banner, what needs the owner (cancellation
/// requests, payment reviews), today's numbers, the team now, the rating
/// summary, and links to the screens not rebuilt yet (FE-OWNER-2).
///
/// Every number comes from the loaded owner jobs and employees lists; a
/// number that cannot be computed honestly is left out.
class OwnerTodayPage extends StatefulWidget {
  const OwnerTodayPage(
      {super.key, required this.onShowTeam, required this.onShowOrders});

  /// Switch the shell to the Team / Orders tab.
  final VoidCallback onShowTeam;
  final VoidCallback onShowOrders;

  @override
  State<OwnerTodayPage> createState() => _OwnerTodayPageState();
}

class _OwnerTodayPageState extends State<OwnerTodayPage> {
  Future<Map<String, dynamic>>? _ratings;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  void _loadRatings() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    setState(() {
      _ratings = context.read<MarketplaceProvider>().fetchRatings(token);
    });
  }

  Future<void> _refresh() async {
    _loadRatings();
    await context.read<OwnerDataController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final user = context.watch<AuthProvider>().user;
    final unread = context.watch<NotificationsProvider>().unreadCount;
    final nav = OwnerNavScope.of(context);

    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, 24, QdSpace.x3, QdSpace.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((user?.username ?? '').trim().isNotEmpty)
                  Text(user!.username.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QdText.secondary.copyWith(color: c.textSecondary)),
                Semantics(
                  header: true,
                  child: Text(l10n.ownTodayTitle,
                      style: QdText.screenTitle.copyWith(color: c.textPrimary)),
                ),
              ],
            ),
          ),
          QdIconButton(
            key: const Key('own_today_bell'),
            icon: Icons.notifications_outlined,
            label: l10n.ownNotifications,
            badgeCount: unread,
            onPressed: () => nav.openNotifications(context),
          ),
        ],
      ),
    );

    Widget content;
    if (!data.loaded && data.jobs.isEmpty) {
      content = const OwnerScrollableCenter(
        key: Key('own_today_loading'),
        child: CircularProgressIndicator(),
      );
    } else if (data.jobsError != null && data.jobs.isEmpty) {
      content = OwnerScrollableCenter(
        key: const Key('own_today_error'),
        child: QdErrorState(
          title: l10n.ownTodayLoadError,
          retrying: data.loading,
          onRetry: _refresh,
        ),
      );
    } else {
      content = _body(context, data, user);
    }

    return SafeArea(
      key: const Key('own_today_page'),
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: RefreshIndicator(onRefresh: _refresh, child: content),
          ),
        ],
      ),
    );
  }

  Widget _body(
      BuildContext context, OwnerDataController data, UserProfile? user) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final nav = OwnerNavScope.of(context);
    final jobs = data.jobs;
    final summary = todaySummary(jobs, data.extrasOf, data.now());
    final requests = pendingCancellationRequests(jobs);
    final reviews = reconciliationCount(jobs);
    final kyb = user?.kycStatus?.trim() ?? '';

    return ListView(
      key: const Key('own_today_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x6),
      children: [
        if (kyb != 'approved') ...[
          OwnerKybBanner(
              status: kyb,
              reason: user?.rejectionReason,
              onOpen: () => nav.openKyb(context)),
          const SizedBox(height: QdSpace.x4),
        ],
        if (data.jobsError != null) ...[
          QdBanner(
            key: const Key('own_today_stale'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: l10n.ownRefreshFailed,
            actionLabel: l10n.retry,
            onAction: _refresh,
          ),
          const SizedBox(height: QdSpace.x4),
        ],
        _SummaryTiles(summary: summary),
        const SizedBox(height: QdSpace.x5),

        // Needs you.
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.warning, shape: BoxShape.circle),
          ),
          const SizedBox(width: QdSpace.x2),
          Semantics(
            header: true,
            child: Text(l10n.ownNeedsYou,
                style: QdText.rowTitle.copyWith(
                    color: c.textPrimary, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 10),
        if (requests.isEmpty && reviews == 0)
          QdCard(
            key: const Key('own_needs_nothing'),
            subtle: true,
            child: Text(l10n.ownNeedsNothing,
                style: QdText.body.copyWith(color: c.textSecondary)),
          ),
        for (var i = 0; i < requests.length; i++) ...[
          _NeedsRow(
            key: Key('own_needs_request_${requests[i].id}'),
            title: l10n.ownNeedsRequestTitle(
                courierNameOf(l10n, data, requests[i].employeeId) ??
                    l10n.ownReconTheCourier),
            subtitle: _requestSubtitle(context, data, requests[i]),
            action: l10n.ownNeedsRespond,
            // One gold button per screen: the oldest request.
            primary: i == 0,
            onTap: () => OwnerOrderDetailPage.open(context, requests[i].id),
          ),
          const SizedBox(height: 10),
        ],
        if (reviews > 0) ...[
          _NeedsRow(
            key: const Key('own_needs_reviews'),
            title: l10n.ownNeedsReviewsTitle(reviews),
            subtitle: l10n.ownNeedsReviewsBody,
            action: l10n.ownNeedsReview,
            primary: false,
            onTap: () => OwnerReconPage.open(context),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: QdSpace.x3),

        // Team now.
        QdSectionHeader(
          title: l10n.ownTeamNow,
          actionLabel: l10n.ownSeeAll,
          onAction: widget.onShowTeam,
        ),
        const SizedBox(height: QdSpace.x2),
        _TeamNow(data: data, onShowTeam: widget.onShowTeam),
        const SizedBox(height: QdSpace.x5),

        _RatingCard(future: _ratings),
        const SizedBox(height: QdSpace.x5),

        QdSectionHeader(title: l10n.ownYourBusiness, small: true),
        const SizedBox(height: 6),
        QdListGroup(children: [
          QdListTile(
            key: const Key('own_link_orders'),
            icon: Icons.receipt_long_outlined,
            title: l10n.ownLinkAllOrders,
            chevron: true,
            onTap: widget.onShowOrders,
          ),
          QdListTile(
            key: const Key('own_link_recon'),
            icon: Icons.gavel_outlined,
            title: l10n.ownReconTitle,
            chevron: true,
            onTap: () => OwnerReconPage.open(context),
          ),
          QdListTile(
            key: const Key('own_link_service'),
            icon: Icons.storefront_outlined,
            title: l10n.ownLinkServiceSetup,
            chevron: true,
            onTap: () => nav.openServiceSetup(context),
          ),
          QdListTile(
            key: const Key('own_link_wallet'),
            icon: Icons.account_balance_wallet_outlined,
            title: l10n.ownLinkWallet,
            chevron: true,
            onTap: () => nav.openWallet(context),
          ),
          QdListTile(
            key: const Key('own_link_subscription'),
            icon: Icons.card_membership_outlined,
            title: l10n.ownLinkSubscription,
            chevron: true,
            onTap: () => nav.openSubscription(context),
          ),
          QdListTile(
            key: const Key('own_link_history'),
            icon: Icons.history,
            title: l10n.ownLinkHistory,
            chevron: true,
            onTap: () => nav.openHistory(context),
          ),
        ]),
      ],
    );
  }

  String _requestSubtitle(
      BuildContext context, OwnerDataController data, Job job) {
    final l10n = context.l10n;
    final reason = job.cancellationRequestReason?.trim() ?? '';
    final parts = <String>[
      reason.isEmpty ? l10n.ownCancelReqNoReason : l10n.ownNeedsReason(reason),
      if (job.cancellationRequestedAt != null)
        formatAgo(context, job.cancellationRequestedAt!, now: data.now()),
    ];
    return parts.join(' · ');
  }
}

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.summary});

  final TodaySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    String count(int n) => summary.truncated ? '$n+' : '$n';
    final tiles = <Widget>[
      _Tile(
          key: const Key('own_tile_ongoing'),
          value: '${summary.ongoingNow}',
          label: l10n.ownTileOngoing),
      _Tile(
          key: const Key('own_tile_delivered'),
          value: count(summary.deliveredToday),
          label: l10n.ownTileDelivered),
      // Left out when a completed COD order has no recorded amount.
      if (summary.cashToday != null)
        _Tile(
            key: const Key('own_tile_cash'),
            value: formatMoney(l10n, summary.cashToday!),
            label: l10n.ownTileCash),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: QdSpace.x2),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          summary.truncated
              ? l10n.ownTodayNoteTruncated(kOwnerJobsServerLimit)
              : l10n.ownTodayNote,
          key: const Key('own_today_note'),
          style: QdText.caption.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsetsDirectional.all(QdSpace.x3),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(QdRadius.button),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  maxLines: 1,
                  style: QdText.amountLg
                      .copyWith(fontSize: 22, color: c.textPrimary)),
            ),
            const SizedBox(height: 2),
            Text(label, style: QdText.caption.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _NeedsRow extends StatelessWidget {
  const _NeedsRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.primary,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String action;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return QdCard(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: QdSpace.x4, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QdText.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: QdSpace.x3),
          primary
              ? QdButton(label: action, small: true, onPressed: onTap)
              : QdButton.secondary(
                  label: action, small: true, onPressed: onTap),
        ],
      ),
    );
  }
}

class _TeamNow extends StatelessWidget {
  const _TeamNow({required this.data, required this.onShowTeam});

  final OwnerDataController data;
  final VoidCallback onShowTeam;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final team = data.employees;
    if (team.isEmpty) {
      return QdCard(
        key: const Key('own_team_now_empty'),
        subtle: true,
        onTap: onShowTeam,
        child: Text(
          data.employeesError != null
              ? l10n.ownTeamLoadError
              : l10n.ownTeamNowEmpty,
          style: QdText.body.copyWith(color: c.textSecondary),
        ),
      );
    }
    const order = [CourierState.onJob, CourierState.free, CourierState.frozen];
    final sorted = [...team]..sort((a, b) => order
        .indexOf(courierStateOf(a, data.jobs))
        .compareTo(order.indexOf(courierStateOf(b, data.jobs))));
    final shown = sorted.take(4).toList();
    return QdListGroup(children: [
      for (final e in shown)
        QdListTile(
          key: Key('own_team_now_${e.id}'),
          leading: QdAvatarInitial(
              name: e.displayName,
              size: 36,
              emphasis: false,
              dimmed: !e.isActive),
          title: e.displayName,
          badge: courierStateChip(l10n, courierStateOf(e, data.jobs)),
          onTap: onShowTeam,
        ),
    ]);
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.future});

  final Future<Map<String, dynamic>>? future;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        // Like the old dashboard: a failed rating fetch hides the card.
        if (future == null || snap.hasError) return const SizedBox.shrink();
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            key: Key('own_rating_loading'),
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final avg = (snap.data?['average_rating'] as num?)?.toDouble() ?? 0;
        final count = (snap.data?['count'] as num?)?.toInt() ?? 0;
        return QdCard(
          key: const Key('own_rating'),
          child: Row(
            children: [
              // Navy, not gold: gold is reserved for the primary action.
              Icon(Icons.star_rounded, color: c.textPrimary, size: 28),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.ownRatingTitle,
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary)),
                    Text(
                      count == 0
                          ? l10n.ownRatingNone
                          : l10n.ownRatingValue(avg.toStringAsFixed(1), count),
                      style: QdText.rowTitleSm.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
