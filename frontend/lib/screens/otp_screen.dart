import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/otp_pin_input.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_success_banner.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  final String? devOtp;

  const OtpScreen({super.key, required this.email, this.devOtp});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  String? _currentDevOtp;

  @override
  void initState() {
    super.initState();
    _currentDevOtp = widget.devOtp;
    // Auto-populate dev OTP in local development mode
    if (_currentDevOtp != null) {
      _otpController.text = _currentDevOtp!;
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resendCode() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final newDevOtp = await auth.resendOtp(widget.email);

    if (!mounted) return;

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _resendCode,
      );
    } else {
      final l10n = AppLocalizations.of(context)!;
      ThemedSnackBar.showSuccess(context, l10n.otpResendSuccessMsg);
      setState(() {
        _currentDevOtp = newDevOtp;
        if (newDevOtp != null) {
          _otpController.text = newDevOtp;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final otp = _otpController.text.trim();

    final success = await auth.verifyOtp(widget.email, otp);

    if (!mounted) return;

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _submit,
      );
    } else if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onBackground),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.security_outlined,
                        size: 36,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.otpTitle,
                    style: AppTypography.headlineLgMobile.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "${l10n.otpSubtitle}\n${widget.email}",
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ThemedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.otpCodeLabel,
                          style: AppTypography.labelLg.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FormField<String>(
                          initialValue: _otpController.text,
                          validator: (val) {
                            final code = (val != null && val.isNotEmpty)
                                ? val.trim()
                                : _otpController.text.trim();
                            if (code.length != 6) {
                              return "OTP must be exactly 6 digits";
                            }
                            return null;
                          },
                          builder: (state) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                OtpPinInput(
                                  controller: _otpController,
                                  hasError: state.hasError,
                                  onChanged: (code) {
                                    state.didChange(code);
                                  },
                                  onCompleted: (code) {
                                    state.didChange(code);
                                    _submit();
                                  },
                                ),
                                if (state.hasError) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Center(
                                    child: Text(
                                      state.errorText ?? '',
                                      style: AppTypography.bodySm.copyWith(
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        if (_currentDevOtp != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.1),
                              border: Border.all(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.4),
                              ),
                              borderRadius: AppRadius.defaultBorder,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bug_report_outlined,
                                    color: AppColors.warning),
                                const SizedBox(width: AppSpacing.base),
                                Expanded(
                                  child: Text(
                                    "Dev Mode: Auto-populated OTP '$_currentDevOtp' from response.",
                                    style: AppTypography.labelMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(
                          text: l10n.otpSubmitButton,
                          isLoading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SecondaryButton(
                          key: const Key('otp_resend_button'),
                          text: l10n.otpResendButton,
                          icon: Icons.refresh,
                          isLoading: auth.isLoading,
                          isOutlined: true,
                          onPressed: _resendCode,
                        ),
                      ],
                    ),
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
