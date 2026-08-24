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
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _currentDevOtp;
  bool _isRequestingCode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains("@")) {
      ThemedSnackBar.showError(context, l10n.loginEmailInvalid);
      return;
    }

    setState(() {
      _isRequestingCode = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();
    final devOtp = await auth.forgotPassword(email);

    if (!mounted) return;

    setState(() {
      _isRequestingCode = false;
      _currentDevOtp = devOtp;
      if (devOtp != null && devOtp.isNotEmpty) {
        _otpController.text = devOtp;
      }
    });

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _requestCode,
      );
    } else {
      final l10n = AppLocalizations.of(context)!;
      ThemedSnackBar.showSuccess(context, l10n.forgotPasswordSentMsg);
    }
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;

    final success = await auth.resetPassword(email, otp, newPassword);

    if (!mounted) return;

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _submitReset,
      );
    } else if (success) {
      final l10n = context.l10n;
      ThemedSnackBar.showSuccess(
        context,
        l10n.passwordResetSuccessMsg,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
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
                // Main Stitch Reset Password Card
                _buildForgotPasswordCard(auth, l10n),
                const SizedBox(height: AppSpacing.lg),

                // External Footer Navigation Link (Back to Login)
                _buildFooterLink(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForgotPasswordCard(AuthProvider auth, AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 4.0,
      padding: AppSpacing.lg,
      elevation: AppElevation.shadowLevel2List,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered Reset Header Block
          _buildHeader(l10n),
          const SizedBox(height: AppSpacing.lg),

          // Dev OTP Disclosure Banner
          if (_currentDevOtp != null) ...[
            _buildDevOtpBanner(),
            const SizedBox(height: AppSpacing.md),
          ],

          // Server Error Banner
          if (auth.error != null) ...[
            ThemedErrorBanner(
              message: auth.error!,
              onRetry: _submitReset,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Email Input Field
          ThemedTextField(
            key: const Key('forgot_password_email_field'),
            controller: _emailController,
            labelText: l10n.loginEmailLabel,
            hintText: l10n.loginEmailHint,
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return l10n.loginEmailReq;
              }
              final emailRegex =
                  RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(val.trim())) {
                return l10n.loginEmailInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xs),

          // Secondary Request Code Action
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SecondaryButton(
              key: const Key('request_reset_code_button'),
              text: l10n.otpResendButton,
              icon: Icons.send_outlined,
              isLoading: _isRequestingCode,
              onPressed: _requestCode,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // OTP Code Form Section
          Text(
            l10n.otpCodeLabel,
            style: AppTypography.labelLg.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FormField<String>(
            key: const Key('forgot_password_otp_field'),
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
          const SizedBox(height: AppSpacing.md),

          // New Password Field
          ThemedTextField(
            key: const Key('forgot_password_new_password_field'),
            controller: _newPasswordController,
            labelText: l10n.signupPasswordLabel,
            hintText: l10n.signupPasswordHint,
            prefixIcon: const Icon(Icons.lock_outline),
            obscureText: true,
            isPasswordField: true,
            validator: (val) {
              if (val == null || val.isEmpty) {
                return l10n.loginPasswordReq;
              }
              if (val.length < 6) {
                return l10n.signupPasswordHint;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Confirm New Password Field
          ThemedTextField(
            key: const Key('forgot_password_confirm_password_field'),
            controller: _confirmPasswordController,
            labelText: l10n.signupConfirmPasswordLabel,
            hintText: l10n.signupConfirmPasswordHint,
            prefixIcon: const Icon(Icons.lock_reset_outlined),
            obscureText: true,
            isPasswordField: true,
            validator: (val) {
              if (val == null || val.isEmpty) {
                return l10n.loginPasswordReq;
              }
              if (val != _newPasswordController.text) {
                return l10n.signupPasswordMismatch;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Primary Submit Reset Action Button
          PrimaryButton(
            key: const Key('submit_reset_password_button'),
            text: l10n.forgotPasswordSubmitButton,
            trailingIcon: Icons.arrow_forward,
            isLoading: auth.isLoading,
            onPressed: _submitReset,
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
          l10n.forgotPasswordSubtitle,
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
