import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/enum_labels.dart';
import '../../l10n/l10n.dart';
import '../../models/payout_request.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import 'activity_log_page.dart';
import 'activity_rules.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_widgets.dart';
import 'plan_rules.dart';

/// Read-only wallet (FE-OWNER-2b, owner decision): balances, withdrawals
/// and the latest money movements. Adding money and withdrawing say "coming
/// soon" and never call the API (payments are cash on delivery only).
///
/// Behaviour kept from WalletScreen: balances, ledger and withdrawals are
/// fetched on open and on pull to refresh (one routine, so a retry always
/// reloads all of them); a loader instead of zero balances before the first
/// load; the load error with retry, and a stale-data banner when a refresh
/// fails over loaded balances; withdrawal amount, method, date, account,
/// status and rejection reason; ledger type, order, balance after and time.
/// Changed: money is shown in EGP (the old screen printed "$"); the ledger
/// shows the latest five with "see all" to the activity log's Money tab;
/// the deposit / payout dialogs are gone (the old screen opened them when
/// the server had digital payments on).
class OwnerWalletPage extends StatefulWidget {
  const OwnerWalletPage({super.key});

  static Future<void> open(BuildContext context) => OwnerNavScope.of(context)
      .push<void>(context, (_) => const OwnerWalletPage());

  @override
  State<OwnerWalletPage> createState() => _OwnerWalletPageState();
}

/// Ledger entries shown on the wallet page; the rest are in the log.
const int kWalletRecentEntries = 5;

class _OwnerWalletPageState extends State<OwnerWalletPage> {
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Balances + ledger, then withdrawals: one after the other, because
  /// OwnerProvider shares one loading flag across calls.
  Future<void> _load() async {
    if (_loading) return;
    final token = context.read<AuthProvider>().token;
    final owner = context.read<OwnerProvider>();
    setState(() => _loading = true);
    if (token != null) await owner.fetchDashboardData(token);
    await owner.fetchPayoutRequests();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedOnce = true;
    });
  }

  void _soon() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('own_wallet_soon'),
        content: Text(context.l10n.digitalPaymentsComingSoon),
      ));
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
        key: Key('own_wallet_loading'),
        child: CircularProgressIndicator(),
      );
    } else if (!owner.isDashboardHydrated) {
      body = OwnerScrollableCenter(
        key: const Key('own_wallet_error'),
        child: QdErrorState(title: l10n.ownWalletLoadError, onRetry: _load),
      );
    } else {
      final ledger = LedgerItem.listFrom(owner.ledgerEntries);
      body = ListView(
        key: const Key('own_wallet_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          if (owner.dashboardError != null) ...[
            QdBanner(
              key: const Key('own_wallet_stale'),
              tone: QdBannerTone.warning,
              message: l10n.ownWalletStale,
              actionLabel: l10n.retry,
              onAction: _load,
            ),
            const SizedBox(height: QdSpace.x3),
          ],
          _Balances(owner: owner),
          const SizedBox(height: QdSpace.x3),
          Row(
            children: [
              Expanded(
                child: QdButton.secondary(
                  key: const Key('own_wallet_add'),
                  label: l10n.ownWalletAddMoney,
                  icon: Icons.add,
                  fullWidth: true,
                  onPressed: _soon,
                ),
              ),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: QdButton.secondary(
                  key: const Key('own_wallet_withdraw'),
                  label: l10n.ownWalletWithdraw,
                  icon: Icons.north_east,
                  fullWidth: true,
                  onPressed: _soon,
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x2),
          Text(l10n.digitalPaymentsComingSoon,
              key: const Key('own_wallet_soon_note'),
              style: QdText.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: QdSpace.x5),
          QdSectionHeader(title: l10n.ownWalletPayouts, small: true),
          const SizedBox(height: 6),
          ..._payouts(context, owner, now),
          const SizedBox(height: QdSpace.x5),
          QdSectionHeader(
            title: l10n.ownWalletRecent,
            small: true,
            actionLabel: ledger.isEmpty ? null : l10n.ownWalletSeeAll,
            onAction: ledger.isEmpty
                ? null
                : () => OwnerActivityPage.open(context, tab: ActivityTab.money),
          ),
          const SizedBox(height: 6),
          if (ledger.isEmpty)
            Text(l10n.ownWalletRecentEmpty,
                key: const Key('own_wallet_recent_empty'),
                style: QdText.body.copyWith(color: c.textSecondary))
          else
            OwnerBorderedColumn(children: [
              for (final e in ledger.take(kWalletRecentEntries))
                ledgerRow(context, e, now: now),
            ]),
        ],
      );
    }

    return Scaffold(
      key: const Key('own_wallet_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: l10n.ownWalletTitle),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }

  List<Widget> _payouts(
      BuildContext context, OwnerProvider owner, DateTime now) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final list = owner.payoutRequests;
    return [
      if (owner.payoutRequestsError != null) ...[
        QdBanner(
          key: const Key('own_wallet_payouts_error'),
          tone: QdBannerTone.warning,
          message: l10n.ownWalletPayoutsError,
          actionLabel: l10n.retry,
          onAction: _load,
        ),
        const SizedBox(height: QdSpace.x3),
      ],
      if (list.isEmpty && owner.payoutRequestsError == null)
        Text(l10n.ownWalletPayoutsEmpty,
            key: const Key('own_wallet_payouts_empty'),
            style: QdText.body.copyWith(color: c.textSecondary))
      else if (list.isNotEmpty)
        OwnerBorderedColumn(children: [
          for (final p in list) _PayoutRow(payout: p, now: now),
        ]),
    ];
  }
}

class _Balances extends StatelessWidget {
  const _Balances({required this.owner});

  final OwnerProvider owner;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    Widget small(String label, double amount, Key key) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: QdText.caption.copyWith(color: c.textSecondary)),
              const SizedBox(height: 2),
              Text(QdMoney.format(l10n, amount),
                  key: key,
                  style: QdText.bodyStrong.copyWith(color: c.textPrimary)),
            ],
          ),
        );
    return QdCard(
      subtle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.ownWalletAvailable,
              style: QdText.secondary.copyWith(color: c.textSecondary)),
          const SizedBox(height: QdSpace.x1),
          Text(QdMoney.format(l10n, owner.withdrawableBalance),
              key: const Key('own_wallet_available'),
              style: QdText.amountLg.copyWith(color: c.textPrimary)),
          const SizedBox(height: QdSpace.x3),
          Container(height: 1, color: c.border),
          const SizedBox(height: QdSpace.x3),
          Row(
            children: [
              small(l10n.ownWalletTotal, owner.walletBalance,
                  const Key('own_wallet_total')),
              const SizedBox(width: QdSpace.x3),
              small(l10n.ownWalletHeld, owner.escrowBalance,
                  const Key('own_wallet_held')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout, required this.now});

  final PayoutRequest payout;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final (label, tone) = payoutStatusChip(l10n, payout.status);
    final reason = payout.rejectionReason?.trim() ?? '';
    final account = payout.accountDetails?.trim() ?? '';
    final rejected = payout.status.trim().toLowerCase() == 'rejected';
    return MergeSemantics(
      child: Container(
        key: Key('own_payout_${payout.id}'),
        color: c.surface,
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: QdSpace.x4, vertical: QdSpace.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(QdMoney.format(l10n, payout.amount),
                      style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                ),
                const SizedBox(width: QdSpace.x2),
                QdStatusChip(label: label, tone: tone),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                payoutMethodLabel(l10n, payout.payoutMethod),
                formatWhen(context, payout.createdAt, now: now),
              ].join(' · '),
              style: QdText.caption.copyWith(color: c.textSecondary),
            ),
            if (account.isNotEmpty)
              Text(account,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QdText.caption.copyWith(color: c.textSecondary)),
            if (rejected && reason.isNotEmpty) ...[
              const SizedBox(height: QdSpace.x1),
              Text(l10n.ownWalletPayoutReason(reason),
                  key: Key('own_payout_reason_${payout.id}'),
                  style: QdText.caption.copyWith(color: c.danger)),
            ],
          ],
        ),
      ),
    );
  }
}
