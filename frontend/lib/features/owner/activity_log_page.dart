import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/audit_labels.dart';
import '../../core/enum_labels.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import 'activity_rules.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_widgets.dart';

enum ActivityTab { activity, money }

/// Activity log: one page with two tabs, Activity (the audit log) and
/// Money (the ledger), replacing OwnerHistoryScreen's activity and ledger
/// tabs and EmployeeScreen's audit tab (the finished-jobs tab is the
/// Orders tab now).
///
/// Behaviour kept: each tab loads when first shown and on pull to refresh
/// (`GET /auth/audit-log` with tenant id + JWT; the ledger through
/// `fetchDashboardData`), a loader while a tab has nothing yet, the load
/// error with retry, an empty state, localized audit action labels and
/// transaction types. New: a period filter (all / today / 7 days), courier
/// names instead of ids, money in / out from the recorded balances.
/// Dropped: the server's English ledger description and the always-empty
/// actor / details lines of the old activity card.
class OwnerActivityPage extends StatefulWidget {
  const OwnerActivityPage({super.key, this.initialTab = ActivityTab.activity});

  final ActivityTab initialTab;

  static Future<void> open(BuildContext context,
          {ActivityTab tab = ActivityTab.activity}) =>
      OwnerNavScope.of(context)
          .push<void>(context, (_) => OwnerActivityPage(initialTab: tab));

  @override
  State<OwnerActivityPage> createState() => _OwnerActivityPageState();
}

class _OwnerActivityPageState extends State<OwnerActivityPage> {
  late ActivityTab _tab = widget.initialTab;
  LogPeriod _period = LogPeriod.all;
  final Set<ActivityTab> _loaded = {};
  final Set<ActivityTab> _loading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(_tab));
  }

  Future<void> _load(ActivityTab tab) async {
    if (_loading.contains(tab)) return;
    final auth = context.read<AuthProvider>();
    final owner = context.read<OwnerProvider>();
    final token = auth.token;
    final ownerId = auth.user?.id;
    setState(() => _loading.add(tab));
    if (token != null && ownerId != null) {
      if (tab == ActivityTab.activity) {
        await owner.fetchAuditLog(tenantId: ownerId, requesterToken: token);
      } else {
        await owner.fetchDashboardData(token);
      }
    }
    if (!mounted) return;
    setState(() {
      _loading.remove(tab);
      _loaded.add(tab);
    });
  }

  void _select(ActivityTab t) {
    setState(() => _tab = t);
    if (!_loaded.contains(t)) _load(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Scaffold(
      key: const Key('own_activity_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: l10n.ownLogTitle),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x1),
            child: QdSegmented<ActivityTab>(
              key: const Key('own_activity_tabs'),
              selected: _tab,
              onChanged: _select,
              segments: [
                QdSegment(
                    value: ActivityTab.activity, label: l10n.ownLogTabActivity),
                QdSegment(value: ActivityTab.money, label: l10n.ownLogTabMoney),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: QdSpace.gutter),
            child: QdChoiceChips<LogPeriod>(
              key: const Key('own_activity_period'),
              semanticLabel: l10n.ownLogPeriodLabel,
              selected: _period,
              onChanged: (p) => setState(() => _period = p),
              choices: [
                QdChoice(value: LogPeriod.all, label: l10n.ownLogPeriodAll),
                QdChoice(value: LogPeriod.today, label: l10n.ownLogPeriodToday),
                QdChoice(value: LogPeriod.week, label: l10n.ownLogPeriodWeek),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(_tab),
              child: _tab == ActivityTab.activity
                  ? _activity(context)
                  : _money(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Loading, error or empty when the tab has nothing to list; null when
  /// it has rows.
  Widget? _state(
    BuildContext context, {
    required ActivityTab tab,
    required int total,
    required int shown,
    required String? error,
    required String errorTitle,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyBody,
  }) {
    final l10n = context.l10n;
    final name = tab.name;
    if (total == 0 && !_loaded.contains(tab)) {
      return OwnerScrollableCenter(
        key: Key('own_${name}_loading'),
        child: const CircularProgressIndicator(),
      );
    }
    if (total == 0 && error != null) {
      return OwnerScrollableCenter(
        key: Key('own_${name}_error'),
        child: QdErrorState(
          title: errorTitle,
          retrying: _loading.contains(tab),
          onRetry: () => _load(tab),
        ),
      );
    }
    if (total == 0) {
      return OwnerScrollableCenter(
        key: Key('own_${name}_empty'),
        child:
            QdEmptyState(icon: emptyIcon, title: emptyTitle, body: emptyBody),
      );
    }
    if (shown == 0) {
      return OwnerScrollableCenter(
        key: Key('own_${name}_none_in_period'),
        child: QdEmptyState(
          icon: Icons.event_busy_outlined,
          title: l10n.ownLogNoneInPeriod,
          actionLabel: l10n.ownLogShowAll,
          onAction: () => setState(() => _period = LogPeriod.all),
        ),
      );
    }
    return null;
  }

  Widget _list(
      BuildContext context, String key, String? staleError, List<Widget> rows) {
    final l10n = context.l10n;
    return ListView(
      key: Key(key),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x4),
      children: [
        if (staleError != null) ...[
          QdBanner(
            key: const Key('own_activity_stale'),
            tone: QdBannerTone.warning,
            message: l10n.ownLogStale,
            actionLabel: l10n.retry,
            onAction: () => _load(_tab),
          ),
          const SizedBox(height: QdSpace.x3),
        ],
        OwnerBorderedColumn(children: rows),
      ],
    );
  }

  Widget _activity(BuildContext context) {
    final l10n = context.l10n;
    final owner = context.watch<OwnerProvider>();
    final data = context.watch<OwnerDataController>();
    final ownerId = context.watch<AuthProvider>().user?.id;
    final all = AuditItem.listFrom(owner.auditLogEntries);
    final shown =
        all.where((e) => inPeriod(_period, e.at, data.now())).toList();
    final state = _state(
      context,
      tab: ActivityTab.activity,
      total: all.length,
      shown: shown.length,
      error: owner.auditLogError,
      errorTitle: l10n.ownLogActivityError,
      emptyIcon: Icons.history,
      emptyTitle: l10n.ownLogActivityEmpty,
      emptyBody: l10n.ownLogActivityEmptyBody,
    );
    if (state != null) return state;

    String? who(AuditItem e) {
      final id = e.employeeId;
      if (id == null) return null;
      if (id == ownerId) return l10n.ownLogYou;
      return courierNameOf(l10n, data, id);
    }

    return _list(context, 'own_activity_list', owner.auditLogError, [
      for (final e in shown)
        _Row(
          key: Key('own_activity_row_${e.id}'),
          icon: Icons.history,
          title: auditActionLabel(l10n, e.action),
          subtitle: [
            if (who(e) != null) who(e)!,
            if (e.at != null) formatAgo(context, e.at!, now: data.now()),
          ].join(' · '),
        ),
    ]);
  }

  Widget _money(BuildContext context) {
    final l10n = context.l10n;
    final owner = context.watch<OwnerProvider>();
    final data = context.watch<OwnerDataController>();
    final all = LedgerItem.listFrom(owner.ledgerEntries);
    final shown =
        all.where((e) => inPeriod(_period, e.at, data.now())).toList();
    final state = _state(
      context,
      tab: ActivityTab.money,
      total: all.length,
      shown: shown.length,
      error: owner.dashboardError,
      errorTitle: l10n.ownLogMoneyError,
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: l10n.ownLogMoneyEmpty,
      emptyBody: l10n.ownLogMoneyEmptyBody,
    );
    if (state != null) return state;

    return _list(context, 'own_money_list', owner.dashboardError, [
      for (final e in shown) ledgerRow(context, e, now: data.now()),
    ]);
  }
}

/// One ledger entry: type, order, balance after, time, and the amount in
/// green (in) or navy (out). Shared with the wallet page.
Widget ledgerRow(BuildContext context, LedgerItem e, {DateTime? now}) {
  final l10n = context.l10n;
  final c = QdColors.of(context);
  final amount = QdMoney.format(l10n, e.amount);
  return _Row(
    key: Key('own_money_row_${e.id}'),
    icon: e.incoming ? Icons.south_west : Icons.north_east,
    iconColor: e.incoming ? c.success : c.textPrimary,
    title: transactionTypeLabel(l10n, e.type),
    subtitle: [
      if (e.jobId != null) jobIdRefIsolated(e.jobId!),
      if (e.hasBalance)
        l10n.ownLogBalanceAfter(QdMoney.format(l10n, e.balanceAfter)),
      if (e.at != null) formatAgo(context, e.at!, now: now),
    ].join(' · '),
    trailing: Semantics(
      label:
          e.incoming ? l10n.ownLogMoneyIn(amount) : l10n.ownLogMoneyOut(amount),
      excludeSemantics: true,
      child: Text(
        amount,
        style: QdText.bodyStrong
            .copyWith(color: e.incoming ? c.success : c.textPrimary),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return MergeSemantics(
      child: Container(
        color: c.surface,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: QdSpace.x4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.fillMuted,
                borderRadius: BorderRadius.circular(QdRadius.sm),
              ),
              child: ExcludeSemantics(
                child: Icon(icon,
                    size: QdSize.icon, color: iconColor ?? c.textPrimary),
              ),
            ),
            const SizedBox(width: QdSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: QdText.caption.copyWith(color: c.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: QdSpace.x2),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
