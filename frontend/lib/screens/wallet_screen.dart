import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';
import '../models/payout_request.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/info_list_tile.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';

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
      body: ownerProvider.isLoading &&
              ownerProvider.ledgerEntries.isEmpty &&
              ownerProvider.walletBalance == 0.0
          ? ThemedLoadingIndicator(message: l10n.walletLoading)
          : RefreshIndicator(
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
                            onPressed: () => _showDepositDialog(context),
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
                        onPressed: () => _showPayoutRequestDialog(context),
                        icon: Icons.outbox_rounded,
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
                        borderRadius: AppRadius.md,
                        padding: AppSpacing.lg,
                        child: ThemedEmptyState(
                          icon: Icons.history_rounded,
                          title: l10n.payoutHistoryEmpty,
                          description:
                              "Submitted payout requests will appear here with processing status.",
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
                        borderRadius: AppRadius.md,
                        padding: AppSpacing.lg,
                        child: ThemedEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: l10n.walletNoTransactions,
                          description:
                              "Your transaction history will appear here once deposits or charges occur.",
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
      title: description.isNotEmpty ? description : type.toUpperCase(),
      subtitleWidget: Row(
        children: [
          Text(
            dateStr,
            style: AppTypography.labelMd.copyWith(
              color: AppColors.outline,
            ),
          ),
          if (jobId.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.base),
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
                  fontSize: 10,
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

  void _showPayoutRequestDialog(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final amountController = TextEditingController();
    final accountDetailsController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedMethod = 'bank_transfer';
    bool isConfirming = false;
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final methodLabel = selectedMethod == 'bank_transfer'
                ? l10n.payoutMethodBankTransfer
                : l10n.payoutMethodInstapay;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(
                isConfirming ? l10n.payoutConfirmTitle : l10n.payoutDialogTitle,
                style: AppTypography.titleMd.copyWith(
                  color: isConfirming ? AppColors.warning : AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: isConfirming
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: AppColors.warning),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: AppColors.warning, size: 28),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    l10n.payoutConfirmMessage(
                                      double.tryParse(amountController.text)
                                              ?.toStringAsFixed(2) ??
                                          amountController.text,
                                      methodLabel,
                                    ),
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            "Account: ${accountDetailsController.text.trim()}",
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (dialogError != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            ThemedErrorBanner(message: dialogError!),
                          ],
                        ],
                      )
                    : Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.payoutDialogDescription,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Amount Field
                            ThemedTextField(
                              key: const Key('payout_amount_field'),
                              controller: amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              labelText: l10n.walletAmountCredits,
                              prefixIcon: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: AppColors.outline),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.payoutErrorAmountInvalid;
                                }
                                final parsed = double.tryParse(value.trim());
                                if (parsed == null || parsed <= 0) {
                                  return l10n.payoutErrorAmountInvalid;
                                }
                                if (parsed >
                                    ownerProvider.withdrawableBalance) {
                                  return l10n.payoutErrorAmountExceeds;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Payout Method Selector
                            DropdownButtonFormField<String>(
                              key: const Key('payout_method_dropdown'),
                              initialValue: selectedMethod,
                              decoration: InputDecoration(
                                labelText: l10n.payoutMethodLabel,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'bank_transfer',
                                  child: Text(l10n.payoutMethodBankTransfer),
                                ),
                                DropdownMenuItem(
                                  value: 'instapay',
                                  child: Text(l10n.payoutMethodInstapay),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    selectedMethod = val;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Account Details Field
                            ThemedTextField(
                              key: const Key('payout_account_details_field'),
                              controller: accountDetailsController,
                              labelText: l10n.payoutAccountDetailsLabel,
                              hintText: selectedMethod == 'bank_transfer'
                                  ? l10n.payoutAccountDetailsBankHint
                                  : l10n.payoutAccountDetailsInstapayHint,
                              prefixIcon: Icon(
                                selectedMethod == 'bank_transfer'
                                    ? Icons.account_balance_rounded
                                    : Icons.phone_android_rounded,
                                color: AppColors.outline,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.payoutErrorDetailsRequired;
                                }
                                return null;
                              },
                            ),
                            if (dialogError != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              ThemedErrorBanner(message: dialogError!),
                            ],
                          ],
                        ),
                      ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: isConfirming ? "Back" : "Cancel",
                        isOutlined: true,
                        onPressed: isSubmitting
                            ? null
                            : () {
                                if (isConfirming) {
                                  setDialogState(() {
                                    isConfirming = false;
                                  });
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        key: isConfirming
                            ? const Key('payout_confirm_button')
                            : const Key('payout_submit_button'),
                        text: isConfirming ? "Confirm Payout" : "Continue",
                        isLoading: isSubmitting,
                        onPressed: () async {
                          if (!isConfirming) {
                            if (formKey.currentState!.validate()) {
                              setDialogState(() {
                                isConfirming = true;
                                dialogError = null;
                              });
                            }
                          } else {
                            setDialogState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });

                            try {
                              final amount =
                                  double.parse(amountController.text.trim());
                              await ownerProvider.requestPayout(
                                amount: amount,
                                payoutMethod: selectedMethod,
                                accountDetails:
                                    accountDetailsController.text.trim(),
                              );
                              await ownerProvider
                                  .fetchDashboardData(auth.token!);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    key: const Key('payout_success_snackbar'),
                                    content: Text(l10n.payoutSuccessMessage),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error requesting payout: $e');
                              setDialogState(() {
                                isSubmitting = false;
                                dialogError = friendlyErrorMessage(e);
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDepositDialog(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    String? dialogError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              title: Text(
                "Deposit Funds",
                style: AppTypography.titleMd.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Enter the amount in credits to deposit to your wallet.",
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ThemedTextField(
                      controller: amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      labelText: l10n.walletAmountCredits,
                      prefixIcon: const Icon(Icons.attach_money,
                          color: AppColors.outline),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Amount is required";
                        }
                        final amount = double.tryParse(value);
                        if (amount == null || amount <= 0) {
                          return "Please enter a valid positive number";
                        }
                        if (amount > 1000000) {
                          return "Maximum single deposit is 1,000,000 credits";
                        }
                        return null;
                      },
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      ThemedErrorBanner(message: dialogError!),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: "Cancel",
                        isOutlined: true,
                        onPressed: isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        text: "Confirm",
                        isLoading: isSubmitting,
                        onPressed: () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() {
                              isSubmitting = true;
                              dialogError = null;
                            });

                            try {
                              final amount =
                                  double.parse(amountController.text);
                              await ownerProvider.deposit(auth.token!, amount);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        "Successfully deposited ${amount.toStringAsFixed(2)} credits."),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error making deposit: $e');
                              setDialogState(() {
                                isSubmitting = false;
                                dialogError = friendlyErrorMessage(e);
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
