import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'primary_button.dart';
import 'themed_error_banner.dart';
import 'themed_success_banner.dart';
import 'themed_text_field.dart';

class EmailChangeDialog extends StatefulWidget {
  const EmailChangeDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const EmailChangeDialog(),
    );
  }

  @override
  State<EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<EmailChangeDialog> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();
  final _newEmailController = TextEditingController();
  final _otpController = TextEditingController();

  int _step = 1;
  bool _isLoading = false;
  String? _errorMessage;
  String? _devOtp;
  String? _targetEmail;

  @override
  void dispose() {
    _newEmailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestCode() async {
    setState(() => _errorMessage = null);
    if (!_emailFormKey.currentState!.validate()) return;

    final newEmail = _newEmailController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() => _isLoading = true);

    try {
      final devOtp = await authProvider.requestEmailChange(newEmail);
      if (mounted) {
        setState(() {
          _step = 2;
          _targetEmail = newEmail;
          _devOtp = devOtp;
          if (devOtp != null && devOtp.isNotEmpty) {
            _otpController.text = devOtp;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = authProvider.error ?? friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleConfirmOtp() async {
    final l10n = context.l10n;
    setState(() => _errorMessage = null);
    if (!_otpFormKey.currentState!.validate()) return;

    final otp = _otpController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() => _isLoading = true);

    try {
      await authProvider.confirmEmailChange(otp);
      if (mounted) {
        ThemedSnackBar.showSuccess(context, l10n.emailChangeSuccess);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = authProvider.error ?? friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.92;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _step == 1
                            ? l10n.changeEmailButton
                            : "Verify New Email",
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('close_email_change_dialog'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (_errorMessage != null) ...[
                  ThemedErrorBanner(
                    key: const Key('email_change_error_banner'),
                    message: _errorMessage!,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_step == 1) ...[
                  Text(
                    l10n.enterNewEmailPrompt,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Form(
                    key: _emailFormKey,
                    child: ThemedTextField(
                      key: const Key('new_email_input'),
                      labelText: l10n.newEmailLabel,
                      controller: _newEmailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.invalidEmailError;
                        }
                        if (!v.contains('@') || !v.contains('.')) {
                          return l10n.invalidEmailError;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    key: const Key('send_email_code_button'),
                    text: l10n.sendVerificationCode,
                    isLoading: _isLoading,
                    onPressed: _handleRequestCode,
                  ),
                ] else ...[
                  Text(
                    l10n.otpSentToEmail(_targetEmail ?? ''),
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_devOtp != null && _devOtp!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ThemedSuccessBanner(
                      key: const Key('dev_otp_banner'),
                      title: l10n.devModeOtpLabel,
                      message: l10n.verificationCodeLine(_devOtp!),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Form(
                    key: _otpFormKey,
                    child: ThemedTextField(
                      key: const Key('email_change_otp_input'),
                      labelText: l10n.verificationCodeLabel,
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return l10n.verificationCodeRequired;
                        }
                        if (v.trim().length < 6) {
                          return "Enter complete 6-digit code";
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    key: const Key('confirm_email_change_button'),
                    text: l10n.confirmEmailChangeButton,
                    isLoading: _isLoading,
                    onPressed: _handleConfirmOtp,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
