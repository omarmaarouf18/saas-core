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
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_success_banner.dart';
import 'reset_password_new_screen.dart';

// Screen 2 of the two-phase reset flow (ADR-0026): verifies the 6-digit
// code via the new AuthProvider.verifyResetCode (POST
// /auth/reset-password/verify-code). On success it pushes the new-password
// screen with the email ONLY — the code is consumed server-side and must
// not be carried forward. Resend reuses AuthProvider.forgotPassword (the
// same call as screen 1); the dev-mode OTP banner/auto-fill moved here
// from the old single screen.
class ResetPasswordOtpScreen extends StatefulWidget {
  final String email;
  final String? devOtp;

  const ResetPasswordOtpScreen({
    super.key,
    required this.email,
    this.devOtp,
  });

  @override
  State<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  String? _currentDevOtp;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _currentDevOtp = widget.devOtp;
    if (_currentDevOtp != null && _currentDevOtp!.isNotEmpty) {
      _otpController.text = _currentDevOtp!;
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();

    final otp = _otpController.text.trim();
    final success = await auth.verifyResetCode(widget.email, otp);

    if (!mounted) return;

    if (!success || auth.error != null) {
      // 429 vs 401 is a status-code distinction the client may react to:
      // the lockout text (with its wait time) comes straight from the
      // server response. The 401 content itself stays uniform server-side.
      setState(() {});
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ResetPasswordNewScreen(email: widget.email),
      ),
    );
  }

  Future<void> _resendCode() async {
    setState(() {
      _isResending = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();
    final devOtp = await auth.forgotPassword(widget.email);

    if (!mounted) return;

    setState(() {
      _isResending = false;
      _currentDevOtp = devOtp;
      if (devOtp != null && devOtp.isNotEmpty) {
        _otpController.text = devOtp;
      }
    });

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _resendCode,
      );
    } else {
      final l10n = AppLocalizations.of(context)!;
      ThemedSnackBar.showSuccess(context, l10n.forgotPasswordSentMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final l10n = context.l10n;

    return FormScreenTemplate(
      appBarBackgroundColor: Colors.transparent,
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
                _buildOtpCard(auth, l10n),
                const SizedBox(height: AppSpacing.lg),
                _buildFooterLink(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpCard(AuthProvider auth, AppLocalizations l10n) {
    final isLockedOut = auth.lastErrorStatusCode == 429;
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 4.0,
      padding: AppSpacing.lg,
      elevation: AppElevation.shadowLevel2List,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(l10n),
          const SizedBox(height: AppSpacing.lg),

          // Dev OTP Disclosure Banner (moved here from the old single screen)
          if (_currentDevOtp != null) ...[
            _buildDevOtpBanner(),
            const SizedBox(height: AppSpacing.md),
          ],

          // Server Error Banner — lockout text (with wait time) for 429,
          // uniform wrong-code text otherwise.
          if (auth.error != null) ...[
            ThemedErrorBanner(
              key: Key(isLockedOut
                  ? 'reset_code_lockout_banner'
                  : 'reset_code_error_banner'),
              message: auth.error!,
              onRetry: isLockedOut ? null : _verifyCode,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // OTP Code Form Section
          Text(
            l10n.otpCodeLabel,
            style: AppTypography.labelLg.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FormField<String>(
            key: const Key('reset_code_otp_field'),
            initialValue: _otpController.text,
            validator: (val) {
              final code = _otpController.text.trim();
              if (code.isEmpty || code.length != 6) {
                return context.l10n.enterOtp6Digits;
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
                    onChanged: (code) => state.didChange(code),
                    onCompleted: (code) => state.didChange(code),
                  ),
                  if (state.hasError) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      state.errorText ?? '',
                      style: AppTypography.bodySm.copyWith(
                        color: context.semanticColors.danger,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Primary Verify Action Button
          PrimaryButton(
            key: const Key('verify_reset_code_button'),
            text: l10n.otpSubmitButton,
            trailingIcon: Icons.arrow_forward,
            isLoading: auth.isLoading,
            onPressed: _verifyCode,
          ),
          const SizedBox(height: AppSpacing.md),

          // Secondary Resend Action
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SecondaryButton(
              key: const Key('resend_reset_code_button'),
              text: l10n.otpResendButton,
              icon: Icons.send_outlined,
              isLoading: _isResending,
              onPressed: _resendCode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
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
                  Icons.lock_reset,
                  size: 32,
                  color: AppColors.secondary,
                ),
              )),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.forgotPasswordTitle,
          style: AppTypography.headlineLgMobile.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          l10n.otpSubtitle,
          style: AppTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDevOtpBanner() {
    return ThemedPanel(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.4),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          context.l10n.devOtpBanner(_currentDevOtp ?? ''),
          style: AppTypography.bodyLg.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ));
  }

  Widget _buildFooterLink(AppLocalizations l10n) {
    return Center(
      child: InkWell(
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Text(
            "${l10n.signupHasAccount} ${l10n.signupSignIn}",
            style: AppTypography.bodyMd.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
