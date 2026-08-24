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

class DepositFundsDialog extends StatefulWidget {
  const DepositFundsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const DepositFundsDialog(),
    );
  }

  @override
  State<DepositFundsDialog> createState() => _DepositFundsDialogState();
}

class _DepositFundsDialogState extends State<DepositFundsDialog> {
  final _amountController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _dialogError;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);

    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(500.0, screenSize.width * 0.92);

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
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.depositFundsTitle,
                          style: AppTypography.titleMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('close_deposit_dialog'),
                        icon: const Icon(Icons.close),
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.depositDialogDesc,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ThemedTextField(
                    key: const Key('deposit_amount_field'),
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    labelText: l10n.walletAmountCredits,
                    prefixIcon: const Icon(
                      Icons.attach_money,
                      color: AppColors.outline,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return l10n.amountRequired;
                      }
                      final amount = double.tryParse(value.trim());
                      if (amount == null || amount <= 0) {
                        return l10n.positiveNumberRequired;
                      }
                      if (amount > 1000000) {
                        return "Maximum single deposit is 1,000,000 credits";
                      }
                      return null;
                    },
                  ),
                  if (_dialogError != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    ThemedErrorBanner(
                      key: const Key('deposit_dialog_error_banner'),
                      message: _dialogError!,
                      onRetry: () => setState(() => _dialogError = null),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          text: l10n.cancel,
                          isOutlined: true,
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: PrimaryButton(
                          key: const Key('deposit_confirm_button'),
                          text: l10n.confirm,
                          isLoading: _isSubmitting,
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              setState(() {
                                _isSubmitting = true;
                                _dialogError = null;
                              });

                              try {
                                final amount =
                                    double.parse(_amountController.text.trim());
                                if (auth.token != null) {
                                  await ownerProvider.deposit(
                                      auth.token!, amount);
                                }
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                  ThemedSnackBar.showSuccess(
                                    context,
                                    "Successfully deposited ${amount.toStringAsFixed(2)} credits.",
                                  );
                                }
                              } catch (e) {
                                debugPrint('Error making deposit: $e');
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
      ),
    );
  }
}
