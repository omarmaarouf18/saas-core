import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
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
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final ownerProvider = Provider.of<OwnerProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: ownerProvider.isLoading &&
              ownerProvider.ledgerEntries.isEmpty &&
              ownerProvider.walletBalance == 0.0
          ? const ThemedLoadingIndicator(message: "Loading wallet...")
          : RefreshIndicator(
              onRefresh: () async {
                await ownerProvider.fetchDashboardData(auth.token!);
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
                          width: 170,
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
                            title: "Total Balance",
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
                            title: "Withdrawable",
                            value: ownerProvider.withdrawableBalance,
                            icon: Icons.check_circle_outline_rounded,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _buildBalanceCard(
                            title: "Locked (Escrow)",
                            value: ownerProvider.escrowBalance,
                            icon: Icons.lock_outline_rounded,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Transaction History Section
                    const ThemedSectionHeader(
                      title: "Transaction Ledger",
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    if (ownerProvider.ledgerEntries.isEmpty)
                      const ThemedCard(
                        borderRadius: AppRadius.md,
                        padding: AppSpacing.lg,
                        child: ThemedEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: "No transactions recorded yet.",
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
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "${value.toStringAsFixed(2)} Credits",
            style: AppTypography.headlineLgMobile.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
        ],
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
        color = Colors.teal;
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

    return ThemedCard(
      borderRadius: AppRadius.defaultValue,
      padding: AppSpacing.md,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            radius: 20,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description.isNotEmpty ? description : type.toUpperCase(),
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
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
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${type == 'deposit' || type == 'refund' || type == 'escrow_release' ? '+' : '-'}${amount.toStringAsFixed(2)}",
                style: AppTypography.bodyLg.copyWith(
                  fontWeight: FontWeight.bold,
                  color: type == 'deposit' ||
                          type == 'refund' ||
                          type == 'escrow_release'
                      ? AppColors.success
                      : AppColors.error,
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
        ],
      ),
    );
  }

  String _twoDigits(int n) => n >= 10 ? "$n" : "0$n";

  void _showDepositDialog(BuildContext context) {
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
                      labelText: "Amount (Credits)",
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
