import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';
import '../models/payout_request.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/deposit_funds_dialog.dart';
import '../widgets/info_list_tile.dart';
import '../widgets/payout_request_dialog.dart';
import '../widgets/primary_button.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';
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

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
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
                  await ownerProvider.fetchDashboardData(auth.token!);
                  await ownerProvider.fetchPlatformConfig();
                  await ownerProvider.fetchPayoutRequests();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "My Wallet",
                            style: AppTypography.headlineLgMobile.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(
                            width: 185,
                            child: PrimaryButton(
                              onPressed: () => DepositFundsDialog.show(context),
                              icon: Icons.add_card_rounded,
                              text: "Deposit Funds",
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Balance Display Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildBalanceCard(
                              title: l10n.walletTotalBalance,
                              value: ownerProvider.walletBalance,
                              icon: Icons.account_balance_rounded,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: _buildBalanceCard(
                              title: l10n.walletWithdrawable,
                              value: ownerProvider.withdrawableBalance,
                              icon: Icons.check_circle_outline_rounded,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: _buildBalanceCard(
                              title: l10n.walletLockedEscrow,
                              value: ownerProvider.escrowBalance,
                              icon: Icons.lock_outline_rounded,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Request Payout Button directly beneath withdrawable balance cards
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

                      if (ownerProvider.platformFeePercentage != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            "Platform fee: ${ownerProvider.platformFeePercentage! % 1 == 0 ? ownerProvider.platformFeePercentage!.toInt() : ownerProvider.platformFeePercentage}%",
                            key: const Key('platform_fee_percentage_text'),
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),

                      // Payout Requests History Section
                      ThemedSectionHeader(
                        key: const Key('payout_history_header'),
                        title: l10n.payoutHistoryTitle,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      if (ownerProvider.payoutRequests.isEmpty)
                        ThemedCard(
                          elevation: AppElevation.shadowLevel1List,
                          borderRadius: AppRadius.md,
                          padding: AppSpacing.lg,
                          child: ThemedEmptyState(
                            icon: Icons.history_rounded,
                            title: l10n.payoutHistoryEmpty,
                            description:
                                "Submitted payout requests will appear here with processing status.",
                            actionText: l10n.payoutWithdrawButton,
                            onActionPressed: () =>
                                PayoutRequestDialog.show(context),
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
                            return _buildPayoutTile(context, payout);
                          },
                        ),
                      const SizedBox(height: AppSpacing.xl),

                      // Transaction History Section
                      ThemedSectionHeader(
                        title: l10n.walletTransactionLedger,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      if (ownerProvider.ledgerEntries.isEmpty)
                        ThemedCard(
                          elevation: AppElevation.shadowLevel1List,
                          borderRadius: AppRadius.md,
                          padding: AppSpacing.lg,
                          child: ThemedEmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: l10n.walletNoTransactions,
                            description:
                                "Your transaction history will appear here once deposits or charges occur.",
                            actionText: "Refresh Wallet",
                            onActionPressed: () =>
                                ownerProvider.fetchDashboardData(auth.token!),
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
                            final entry = ownerProvider.ledgerEntries[index];
                            return _buildLedgerTile(entry);
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBalanceCard({
    required String title,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return StatCard(
      label: title,
      value: "${value.toStringAsFixed(2)} Credits",
      icon: icon,
      iconColor: color,
    );
  }

  Widget _buildPayoutTile(BuildContext context, PayoutRequest payout) {
    final l10n = context.l10n;
    final isBank = payout.payoutMethod == 'bank_transfer';
    final methodLabel = isBank
        ? l10n.payoutMethodBankTransfer
        : (payout.payoutMethod == 'instapay'
            ? l10n.payoutMethodInstapay
            : payout.payoutMethod.toUpperCase());

    final dateStr =
        "${payout.createdAt.year}-${_twoDigits(payout.createdAt.month)}-${_twoDigits(payout.createdAt.day)} ${_twoDigits(payout.createdAt.hour)}:${_twoDigits(payout.createdAt.minute)}";

    return InfoListTile(
      key: Key('payout_tile_${payout.id}'),
      leadingIcon:
          isBank ? Icons.account_balance_rounded : Icons.phone_android_rounded,
      leadingIconColor: AppColors.primary,
      leadingBackgroundColor: AppColors.primary.withValues(alpha: 0.1),
      title: "${payout.amount.toStringAsFixed(2)} Credits",
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$methodLabel • $dateStr",
            style: AppTypography.labelMd.copyWith(color: AppColors.outline),
          ),
          if (payout.accountDetails != null &&
              payout.accountDetails!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              payout.accountDetails!,
              style: AppTypography.labelMd
                  .copyWith(color: AppColors.onSurfaceVariant),
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
                color: AppColors.error,
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
        color = AppColors.success;
        break;
      case 'escrow_lock':
        icon = Icons.lock_outline_rounded;
        color = AppColors.warning;
        break;
      case 'escrow_release':
        icon = Icons.lock_open_rounded;
        color = AppColors.primary;
        break;
      case 'refund':
        icon = Icons.replay_rounded;
        color = AppColors.success;
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
          : type.replaceAll('_', ' ').toUpperCase(),
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: AppTypography.labelMd.copyWith(color: AppColors.outline),
          ),
          if (jobId.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                "Job: ${jobId.substring(0, jobId.length > 8 ? 8 : jobId.length)}",
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
              color: isPositive ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "Bal: ${balanceAfter.toStringAsFixed(2)}",
            style: AppTypography.labelMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";
}
