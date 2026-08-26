import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_error_banner.dart';
import 'themed_success_banner.dart';
import 'themed_text_field.dart';

class PayoutRequestDialog extends StatefulWidget {
  const PayoutRequestDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PayoutRequestDialog(),
    );
  }

  @override
  State<PayoutRequestDialog> createState() => _PayoutRequestDialogState();
}

class _PayoutRequestDialogState extends State<PayoutRequestDialog> {
  final _amountController = TextEditingController();
  final _accountDetailsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _selectedMethod = 'bank_transfer';
  bool _isConfirming = false;
  bool _isSubmitting = false;
  String? _dialogError;

  @override
  void dispose() {
    _amountController.dispose();
    _accountDetailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(500.0, screenSize.width * 0.92);

    final methodLabel = _selectedMethod == 'bank_transfer'
        ? l10n.payoutMethodBankTransfer
        : l10n.payoutMethodInstapay;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _isConfirming
                            ? l10n.payoutConfirmTitle
                            : l10n.payoutDialogTitle,
                        style: AppTypography.titleMd.copyWith(
                          color: _isConfirming
                              ? context.semanticColors.warning
                              : AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('close_payout_dialog'),
                      icon: const Icon(Icons.close),
                      tooltip: context.l10n.tooltipClose,
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Content: Step 1 or Step 2
                if (_isConfirming) ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color:
                          context.semanticColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.semanticColors.warning),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: context.semanticColors.warning,
                          size: 28,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.payoutConfirmMessage(
                              double.tryParse(_amountController.text)
                                      ?.toStringAsFixed(2) ??
                                  _amountController.text,
                              methodLabel,
                            ),
                            style: AppTypography.bodyMd.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.accountDetailsLine(
                        _accountDetailsController.text.trim()),
                    style: AppTypography.labelMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_dialogError != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    ThemedErrorBanner(
                      key: const Key('payout_dialog_error_banner'),
                      message: _dialogError!,
                      onRetry: () => setState(() => _dialogError = null),
                    ),
                  ],
                ] else ...[
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.payoutDialogDescription,
                          style: AppTypography.bodyMd.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Amount Field
                        ThemedTextField(
                          key: const Key('payout_amount_field'),
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          labelText: l10n.walletAmountCredits,
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: AppColors.outline,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return l10n.payoutErrorAmountInvalid;
                            }
                            final parsed = double.tryParse(value.trim());
                            if (parsed == null || parsed <= 0) {
                              return l10n.payoutErrorAmountInvalid;
                            }
                            if (parsed > ownerProvider.withdrawableBalance) {
                              return l10n.payoutErrorAmountExceeds;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Payout Method Selector
                        DropdownButtonFormField<String>(
                          key: const Key('payout_method_dropdown'),
                          initialValue: _selectedMethod,
                          decoration: InputDecoration(
                            labelText: l10n.payoutMethodLabel,
                            labelStyle: AppTypography.labelLg.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.md,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: AppRadius.defaultBorder,
                              borderSide: const BorderSide(
                                color: AppColors.outlineVariant,
                                width: 1,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: AppRadius.defaultBorder,
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
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
                              setState(() {
                                _selectedMethod = val;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Account Details Field
                        ThemedTextField(
                          key: const Key('payout_account_details_field'),
                          controller: _accountDetailsController,
                          labelText: l10n.payoutAccountDetailsLabel,
                          hintText: _selectedMethod == 'bank_transfer'
                              ? l10n.payoutAccountDetailsBankHint
                              : l10n.payoutAccountDetailsInstapayHint,
                          prefixIcon: Icon(
                            _selectedMethod == 'bank_transfer'
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
                        if (_dialogError != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          ThemedErrorBanner(
                            key: const Key('payout_dialog_error_banner'),
                            message: _dialogError!,
                            onRetry: () => setState(() => _dialogError = null),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: _isConfirming ? "Back" : "Cancel",
                        isOutlined: true,
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                if (_isConfirming) {
                                  setState(() {
                                    _isConfirming = false;
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
                        key: _isConfirming
                            ? const Key('payout_confirm_button')
                            : const Key('payout_submit_button'),
                        text: _isConfirming ? "Confirm Payout" : "Continue",
                        isLoading: _isSubmitting,
                        onPressed: () async {
                          if (!_isConfirming) {
                            if (_formKey.currentState!.validate()) {
                              setState(() {
                                _isConfirming = true;
                                _dialogError = null;
                              });
                            }
                          } else {
                            setState(() {
                              _isSubmitting = true;
                              _dialogError = null;
                            });

                            try {
                              final amount =
                                  double.parse(_amountController.text.trim());
                              await ownerProvider.requestPayout(
                                amount: amount,
                                payoutMethod: _selectedMethod,
                                accountDetails:
                                    _accountDetailsController.text.trim(),
                              );
                              if (auth.token != null) {
                                await ownerProvider
                                    .fetchDashboardData(auth.token!);
                              }
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                ThemedSnackBar.showSuccess(
                                  context,
                                  l10n.payoutSuccessMessage,
                                  key: const Key('payout_success_snackbar'),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error requesting payout: $e');
                              if (mounted) {
                                setState(() {
                                  _isSubmitting = false;
                                  _dialogError = friendlyErrorMessage(e);
                                });
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
