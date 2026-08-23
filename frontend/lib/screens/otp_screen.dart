import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
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

    return FormScreenTemplate(
      backgroundColor: AppColors.background,
      appBarBackgroundColor: Colors.transparent,
      appBarForegroundColor: AppColors.onBackground,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.marginMobile,
        vertical: AppSpacing.md,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Main Stitch Verification Card
                _buildOtpCard(auth, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpCard(AuthProvider auth, AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 4.0,
      padding: AppSpacing.lg,
      elevation: AppElevation.shadowLevel2List,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Security Shield Icon Container
          _buildSecurityHeader(l10n),
          const SizedBox(height: AppSpacing.lg),

          // Subtitle and Target Prompt
          Text(
            l10n.otpCodeLabel,
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),

          // 6-Digit PIN Discrete Input Fields
          _buildPinInput(),

          // Dev Mode Code Disclosure Banner
          if (_currentDevOtp != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildDevModeBanner(),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Action Buttons: Verify & Resend
          _buildActionButtons(auth, l10n),
          const SizedBox(height: AppSpacing.md),

          // Contextual Security Trust Footnote
          _buildSecurityFootnote(),
        ],
      ),
    );
  }

  Widget _buildSecurityHeader(AppLocalizations l10n) {
    return Column(
      children: [
        const Center(
          child: ThemedPanel(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
              width: 64,
              height: 64,
              child: Center(
                child: Icon(
                  Icons.security_outlined,
                  size: 32,
                  color: AppColors.secondary,
                ),
              )),
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
        const SizedBox(height: AppSpacing.xxs),
        Text(
          "${l10n.otpSubtitle}\n${widget.email}",
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPinInput() {
    return FormField<String>(
      initialValue: _otpController.text,
      validator: (val) {
        final code = (val != null && val.isNotEmpty)
            ? val.trim()
            : _otpController.text.trim();
        if (code.length != 6) {
          return context.l10n.otpExactly6Digits;
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
    );
  }

  Widget _buildDevModeBanner() {
    return ThemedPanel(
        color: AppColors.secondary.withValues(alpha: 0.1),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const Icon(
              Icons.bug_report_outlined,
              color: AppColors.warning,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                context.l10n.devOtpAutoFilled(_currentDevOtp ?? ''),
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ));
  }

  Widget _buildActionButtons(AuthProvider auth, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          text: l10n.otpSubmitButton,
          trailingIcon: Icons.arrow_forward,
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
    );
  }

  Widget _buildSecurityFootnote() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xxs,
      children: [
        const Icon(
          Icons.lock_outline,
          size: 14,
          color: AppColors.outline,
        ),
        Text(
          context.l10n.enterpriseTrustNote,
          style: AppTypography.caption.copyWith(
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}
