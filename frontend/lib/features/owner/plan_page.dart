import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import 'owner_controller.dart';
import 'owner_nav.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';
import 'plan_rules.dart';

/// Plan (FE-OWNER-2b): the current tier, whether customers can find and
/// book the business (ADR-0024), what the paid plan includes, and the plan
/// change actions (owner decision, revised): "Request upgrade" posts
/// `tier=paid`, which the server stores as `pending_payment` (202) until an
/// admin activates it in the reviewer console and support contacts the
/// owner; while pending the plan shows "Under review" and the button is
/// disabled. "Switch to free" stays available for a paid or pending plan
/// (the server switches at once). Both ask first in a confirm sheet; no
/// payment is explained or taken in the app.
///
/// Behaviour kept from SubscriptionScreen: the plan is fetched on open
/// (also when the dashboard data was never loaded), a loader instead of the
/// default "free" tier before the first load, the load error with retry,
/// the pending note, a confirm before either change (switching to free is
/// destructive), success and failure notices with retry, one change at a
/// time. New: the expiry date, whether the business is open to customers,
/// the plan reloaded after a change. Dropped: the made-up "$0" / "$19.99"
/// prices and the feature lists the server does not enforce (only listing,
/// bookings, service setup and live courier location depend on the paid
/// plan).
class OwnerPlanPage extends StatefulWidget {
  const OwnerPlanPage({super.key});

  static Future<void> open(BuildContext context) => OwnerNavScope.of(context)
      .push<void>(context, (_) => const OwnerPlanPage());

  @override
  State<OwnerPlanPage> createState() => _OwnerPlanPageState();
}

class _OwnerPlanPageState extends State<OwnerPlanPage> {
  bool _loading = false;
  bool _loadedOnce = false;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    final token = context.read<AuthProvider>().token;
    setState(() => _loading = true);
    if (token != null) {
      await context.read<OwnerProvider>().fetchDashboardData(token);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedOnce = true;
    });
  }

  /// Asks first, then requests [tier] ('paid' or 'free').
  Future<void> _confirmChange(String tier) async {
    if (_changing) return;
    final l10n = context.l10n;
    final toFree = tier == 'free';
    final pending =
        planTierOf(context.read<OwnerProvider>().subscriptionTier) ==
            PlanTier.pending;
    final ok = await showOwnerConfirmSheet(
      context,
      key: Key(toFree ? 'own_plan_downgrade_sheet' : 'own_plan_upgrade_sheet'),
      title: toFree ? l10n.ownPlanDowngradeTitle : l10n.ownPlanUpgradeTitle,
      message: toFree
          ? (pending
              ? l10n.ownPlanDowngradeBodyPending
              : l10n.ownPlanDowngradeBodyPaid)
          : l10n.ownPlanUpgradeBody,
      confirmLabel: toFree ? l10n.ownPlanDowngrade : l10n.ownPlanUpgradeSend,
      destructive: toFree,
    );
    if (ok && mounted) await _change(tier);
  }

  Future<void> _change(String tier) async {
    if (_changing) return;
    final l10n = context.l10n;
    final token = context.read<AuthProvider>().token;
    final owner = context.read<OwnerProvider>();
    if (token == null) return;
    setState(() => _changing = true);
    try {
      await owner.updateSubscription(tenantId: token, tier: tier);
      if (!mounted) return;
      showOwnerNotice(context,
          tier == 'free' ? l10n.ownPlanDowngraded : l10n.ownPlanUpgradeSent);
      // The server's view (tier and expiry) after the change.
      await owner.fetchDashboardData(token);
    } catch (e) {
      if (!mounted) return;
      // 429 carries the wait time; everything else gets the friendly copy.
      final msg = e is ApiClientException && e.statusCode == 429
          ? e.message
          : friendlyErrorMessage(e);
      showOwnerNotice(context, msg, onRetry: () => _change(tier));
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  /// Request upgrade (gold; disabled while a request is under review) for
  /// any plan that is not an open paid one, and switch to free for a paid
  /// or pending plan.
  List<Widget> _actions(BuildContext context, String tier, PlanAccess access) {
    final l10n = context.l10n;
    final t = planTierOf(tier);
    final pending = t == PlanTier.pending;
    final canUpgrade =
        pending || access == PlanAccess.closed || access == PlanAccess.expired;
    final canDowngrade = t == PlanTier.paid || pending;
    return [
      if (canUpgrade) ...[
        QdButton(
          key: const Key('own_plan_upgrade'),
          label: l10n.ownPlanRequestUpgrade,
          icon: Icons.workspace_premium_outlined,
          fullWidth: true,
          loading: _changing && !pending,
          onPressed: pending || _changing ? null : () => _confirmChange('paid'),
        ),
        const SizedBox(height: QdSpace.x2),
      ],
      if (canDowngrade) ...[
        QdButton.destructive(
          key: const Key('own_plan_downgrade'),
          label: l10n.ownPlanDowngrade,
          fullWidth: true,
          onPressed: _changing ? null : () => _confirmChange('free'),
        ),
        const SizedBox(height: QdSpace.x1),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final owner = context.watch<OwnerProvider>();
    final now = context.read<OwnerDataController>().now();

    Widget body;
    if (!owner.isDashboardHydrated && (_loading || !_loadedOnce)) {
      body = const OwnerScrollableCenter(
        key: Key('own_plan_loading'),
        child: CircularProgressIndicator(),
      );
    } else if (!owner.isDashboardHydrated) {
      body = OwnerScrollableCenter(
        key: const Key('own_plan_error'),
        child: QdErrorState(title: l10n.ownPlanLoadError, onRetry: _load),
      );
    } else {
      final tier = owner.subscriptionTier;
      final access = planAccessOf(tier, owner.subscriptionExpiresAt, now);
      body = ListView(
        key: const Key('own_plan_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          if (owner.dashboardError != null) ...[
            QdBanner(
              key: const Key('own_plan_stale'),
              tone: QdBannerTone.warning,
              message: l10n.ownWalletStale,
              actionLabel: l10n.retry,
              onAction: _load,
            ),
            const SizedBox(height: QdSpace.x3),
          ],
          _Current(
            tier: tier,
            access: access,
            expiresAt: owner.subscriptionExpiresAt,
          ),
          if (planTierOf(tier) == PlanTier.pending) ...[
            const SizedBox(height: QdSpace.x3),
            QdBanner(
              key: const Key('own_plan_pending'),
              tone: QdBannerTone.warning,
              message: l10n.ownPlanPendingNote,
            ),
          ],
          const SizedBox(height: QdSpace.x5),
          QdSectionHeader(title: l10n.ownPlanIncludes, small: true),
          const SizedBox(height: 6),
          OwnerBorderedColumn(children: [
            for (final f in [
              l10n.ownPlanFeatureListed,
              l10n.ownPlanFeatureService,
              l10n.ownPlanFeatureTracking,
              l10n.ownPlanFeatureNoCommission,
            ])
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: QdSpace.x4, vertical: QdSpace.x3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check, size: QdSize.icon, color: c.success),
                    const SizedBox(width: QdSpace.x3),
                    Expanded(
                      child: Text(f,
                          style: QdText.body.copyWith(color: c.textPrimary)),
                    ),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: QdSpace.x5),
          QdSectionHeader(title: l10n.ownPlanChangeTitle, small: true),
          const SizedBox(height: 6),
          Text(l10n.ownPlanChangeBody,
              style: QdText.body.copyWith(color: c.textPrimary)),
          const SizedBox(height: QdSpace.x3),
          ..._actions(context, tier, access),
          QdButton.text(
            key: const Key('own_plan_support'),
            label: l10n.ownPlanContactSupport,
            icon: Icons.support_agent,
            fullWidth: true,
            onPressed: () => OwnerNavScope.of(context).openSupport(context),
          ),
        ],
      );
    }

    return Scaffold(
      key: const Key('own_plan_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: l10n.ownPlanTitle),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

class _Current extends StatelessWidget {
  const _Current(
      {required this.tier, required this.access, required this.expiresAt});

  final String tier;
  final PlanAccess access;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final date = expiresAt == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).languageCode)
            .format(expiresAt!.toLocal());
    final open = access == PlanAccess.open || access == PlanAccess.openUntil;
    final line = switch (access) {
      PlanAccess.open => l10n.ownPlanOpen,
      PlanAccess.openUntil => l10n.ownPlanOpenUntil(date),
      PlanAccess.expired => l10n.ownPlanExpired(date),
      PlanAccess.closed => l10n.ownPlanClosed,
    };
    return QdCard(
      key: Key('own_plan_${access.name}'),
      subtle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.ownPlanYours,
              style: QdText.secondary.copyWith(color: c.textSecondary)),
          const SizedBox(height: QdSpace.x1),
          Text(planLabel(l10n, tier),
              key: const Key('own_plan_tier'),
              style: QdText.sheetTitle.copyWith(color: c.textPrimary)),
          const SizedBox(height: QdSpace.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(open ? Icons.storefront_outlined : Icons.visibility_off,
                  size: QdSize.icon, color: open ? c.success : c.warning),
              const SizedBox(width: QdSpace.x2),
              Expanded(
                child: Text(line,
                    key: const Key('own_plan_access'),
                    style: QdText.body.copyWith(color: c.textPrimary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
