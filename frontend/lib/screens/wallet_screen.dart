import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';
import '../models/payout_request.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/deposit_funds_dialog.dart';
import '../widgets/info_list_tile.dart';
import '../widgets/payout_request_dialog.dart';
import '../widgets/primary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/app_shell.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_section_header.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
      ownerProvider.fetchPlatformConfig();
      ownerProvider.fetchPayoutRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return AppShell(
      title: l10n.walletMyWalletTitle,
      body: AnimatedSwitcher(
        duration: AppMotion.durationMedium,
        switchInCurve: AppMotion.curveStateChange,
        switchOutCurve: AppMotion.curveStateChange,
        child: (ownerProvider.isLoading &&
                ownerProvider.ledgerEntries.isEmpty &&
                ownerProvider.walletBalance == 0.0)
            ? const Padding(
                key: ValueKey('wallet_skeleton_loader'),
                padding: EdgeInsets.all(AppSpacing.lg),
                child: WalletScreenSkeleton(),
              )
            : RefreshIndicator(
                key: const ValueKey('wallet_content'),
                onRefresh: () async {
                  if (auth.token != null) {
                    await ownerProvider.fetchDashboardData(auth.token!);
                  }
                  await ownerProvider.fetchPlatformConfig();
                  await ownerProvider.fetchPayoutRequests();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row (Stitch Reference)
                      _buildHeader(l10n),
                      const SizedBox(height: AppSpacing.lg),

                      // Bento Financial Grid: Available Balance Hero & Escrow Pending
                      _buildHeroBalanceCard(ownerProvider, l10n),
                      const SizedBox(height: AppSpacing.md),

                      // Balance Breakdown Cards (Total, Withdrawable, Escrow)
                      _buildBalanceCardsRow(ownerProvider, l10n),
                      const SizedBox(height: AppSpacing.md),

                      // Payout Request Action Button
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          key: const Key('request_payout_button'),
                          onPressed: () => PayoutRequestDialog.show(context),
                          icon: Icons.outbox_rounded,
                          trailingIcon: Icons.arrow_forward,
                          text: l10n.payoutWithdrawButton,
                        ),
                      ),

                      // Platform Fee Indicator
                      if (ownerProvider.platformFeePercentage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            l10n.platformFeeLine(
                                ownerProvider.platformFeePercentage! % 1 == 0
                                    ? ownerProvider.platformFeePercentage!
                                        .toInt()
                                        .toString()
                                    : "${ownerProvider.platformFeePercentage}"),
                            key: const Key('platform_fee_percentage_text'),
                            style: AppTypography.labelMd.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),

                      // Payout Requests History Section
                      _buildPayoutSection(ownerProvider, l10n),
                      const SizedBox(height: AppSpacing.xl),

                      // Transaction History Section
                      _buildLedgerSection(ownerProvider, auth, l10n),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    // Screen title lives in the AppBar now; the in-body heading would
    // duplicate it, so only the subtitle stays next to the deposit action.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            l10n.walletCorporateSubtitle,
            style: AppTypography.bodyMd.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 160,
          child: PrimaryButton(
            onPressed: () => DepositFundsDialog.show(context),
            icon: Icons.add_card_rounded,
            text: l10n.depositFundsTitle,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroBalanceCard(
    OwnerProvider ownerProvider,
    AppLocalizations l10n,
  ) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 3,
      color: AppColors.primaryContainer,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.availableBalanceBadge,
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.onPrimaryContainer,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ThemedPanel(
                  color: context.semanticColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.baseSm,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.trending_up,
                        color: context.semanticColors.success,
                        size: 14,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        l10n.balanceTrendChipMock,
                        style: AppTypography.caption.copyWith(
                          color: context.semanticColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "\$${ownerProvider.withdrawableBalance.toStringAsFixed(2)}",
            style: AppTypography.headlineLg.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.totalPortfolioLine(
                ownerProvider.walletBalance.toStringAsFixed(2)),
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCardsRow(
    OwnerProvider ownerProvider,
    AppLocalizations l10n,
  ) {
    // Declutter V2: the three full StatCards collapse into one slim inline
    // breakdown row (the hero already carries the headline balances).
    return ThemedCard(
      elevation: AppElevation.shadowLevel1List,
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Row(
        children: [
          Expanded(
            child: _breakdownItem(
              l10n.walletTotalBalance,
              ownerProvider.walletBalance.toStringAsFixed(0),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
              width: 1,
              height: 28,
              color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _breakdownItem(
              l10n.walletWithdrawable,
              ownerProvider.withdrawableBalance.toStringAsFixed(0),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
              width: 1,
              height: 28,
              color: AppColors.outlineVariant.withValues(alpha: 0.4)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _breakdownItem(
              l10n.walletLockedEscrow,
              ownerProvider.escrowBalance.toStringAsFixed(0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: AppTypography.bodyLg.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPayoutSection(
    OwnerProvider ownerProvider,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemedSectionHeader(
          key: const Key('payout_history_header'),
          title: l10n.payoutHistoryTitle,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (ownerProvider.payoutRequests.isEmpty)
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: ThemedEmptyState(
              icon: Icons.history_rounded,
              title: l10n.payoutHistoryEmpty,
              description: l10n.walletPayoutEmptyHint,
              actionText: l10n.payoutWithdrawButton,
              onActionPressed: () => PayoutRequestDialog.show(context),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ownerProvider.payoutRequests.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.base),
            itemBuilder: (context, index) {
              final payout = ownerProvider.payoutRequests[index];
              return _buildPayoutTile(context, payout, l10n);
            },
          ),
      ],
    );
  }

  Widget _buildLedgerSection(
    OwnerProvider ownerProvider,
    AuthProvider auth,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemedSectionHeader(
          title: l10n.walletTransactionLedger,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (ownerProvider.ledgerEntries.isEmpty)
          ThemedCard(
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: ThemedEmptyState(
              icon: Icons.receipt_long_outlined,
              title: l10n.walletNoTransactions,
              description: l10n.walletLedgerEmptyHint,
              actionText: l10n.refreshWalletBtn,
              onActionPressed: () {
                if (auth.token != null) {
                  ownerProvider.fetchDashboardData(auth.token!);
                }
              },
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ownerProvider.ledgerEntries.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.base),
            itemBuilder: (context, index) {
              return _buildLedgerTile(ownerProvider.ledgerEntries[index]);
            },
          ),
      ],
    );
  }

  Widget _buildPayoutTile(
    BuildContext context,
    PayoutRequest payout,
    AppLocalizations l10n,
  ) {
    final isBank = payout.payoutMethod == 'bank_transfer';
    final methodLabel = isBank
        ? l10n.payoutMethodBankTransfer
        : (payout.payoutMethod == 'instapay'
            ? l10n.payoutMethodInstapay
            : AppTypography.uppercaseLabel(payout.payoutMethod));

    final dateStr =
        "${payout.createdAt.year}-${_twoDigits(payout.createdAt.month)}-${_twoDigits(payout.createdAt.day)} ${_twoDigits(payout.createdAt.hour)}:${_twoDigits(payout.createdAt.minute)}";

    return InfoListTile(
      key: Key('payout_tile_${payout.id}'),
      leadingIcon:
          isBank ? Icons.account_balance_rounded : Icons.phone_android_rounded,
      leadingIconColor: AppColors.primary,
      leadingBackgroundColor: AppColors.primary.withValues(alpha: 0.1),
      title: l10n.creditsAmountLine(payout.amount.toStringAsFixed(2)),
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$methodLabel • $dateStr",
            style: AppTypography.labelMd.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (payout.accountDetails != null &&
              payout.accountDetails!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              payout.accountDetails!,
              style: AppTypography.labelMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (payout.status.toLowerCase() == 'rejected' &&
              payout.rejectionReason != null &&
              payout.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              "${l10n.payoutRejectionReasonLabel} ${payout.rejectionReason}",
              key: Key('payout_rejection_reason_${payout.id}'),
              style: AppTypography.labelMd.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
      trailing: StatusBadge(
        key: Key('payout_status_badge_${payout.id}'),
        status: payout.status,
        compact: true,
      ),
    );
  }

  Widget _buildLedgerTile(Map<String, dynamic> entry) {
    final type = entry['type'] ?? '';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (entry['balance_after'] as num?)?.toDouble() ?? 0.0;
    final description = entry['description'] ?? '';
    final jobId = entry['job_id'] ?? '';

    DateTime? timestamp;
    if (entry['timestamp'] != null) {
      try {
        timestamp = DateTime.parse(entry['timestamp']).toLocal();
      } catch (_) {}
    }

    IconData icon;
    Color color;

    switch (type) {
      case 'deposit':
        icon = Icons.add_circle_outline_rounded;
        color = context.semanticColors.success;
        break;
      case 'escrow_lock':
        icon = Icons.lock_outline_rounded;
        color = context.semanticColors.warning;
        break;
      case 'escrow_release':
        icon = Icons.lock_open_rounded;
        color = AppColors.primary;
        break;
      case 'refund':
        icon = Icons.replay_rounded;
        color = context.semanticColors.success;
        break;
      case 'fee_deduction':
        icon = Icons.remove_circle_outline_rounded;
        color = AppColors.error;
        break;
      default:
        icon = Icons.monetization_on_outlined;
        color = AppColors.outline;
    }

    final dateStr = timestamp != null
        ? "${timestamp.year}-${_twoDigits(timestamp.month)}-${_twoDigits(timestamp.day)} ${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}"
        : "";

    final isPositive =
        type == 'deposit' || type == 'refund' || type == 'escrow_release';

    return InfoListTile(
      leadingIcon: icon,
      leadingIconColor: color,
      leadingBackgroundColor: color.withValues(alpha: 0.1),
      title: description.isNotEmpty
          ? description
          : AppTypography.uppercaseLabel(type.replaceAll('_', ' ')),
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: AppTypography.labelMd.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (jobId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            ThemedPanel(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                child: Text(
                  context.l10n.ledgerJobLine(
                      jobId.substring(0, jobId.length > 8 ? 8 : jobId.length)),
                  style: AppTypography.labelMd.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                )),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            "${isPositive ? '+' : '-'}${amount.toStringAsFixed(2)}",
            style: AppTypography.bodyLg.copyWith(
              fontWeight: FontWeight.bold,
              color:
                  isPositive ? context.semanticColors.success : AppColors.error,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.ledgerBalanceLine(balanceAfter.toStringAsFixed(2)),
            style: AppTypography.labelMd.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";
}
