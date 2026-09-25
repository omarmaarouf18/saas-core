import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'forgot_password_screen.dart';
import 'login_screen.dart';

// Screen 3 of the two-phase reset flow (ADR-0026 as amended): collects the
// new password and calls the modified AuthProvider.resetPassword(email,
// resetToken, newPassword) — the token comes from the provider state set by
// screen 2's verify, never re-derived. No raw code is sent or needed. On
// success: success snackbar + navigate to LoginScreen clearing the stack
// (same as before). On failure (e.g. the token expired because the user sat
// on this screen too long) it shows a restart-from-email error — no silent
// retry loop.
class ResetPasswordNewScreen extends StatefulWidget {
  final String email;

  const ResetPasswordNewScreen({super.key, required this.email});

  @override
  State<ResetPasswordNewScreen> createState() => _ResetPasswordNewScreenState();
}

class _ResetPasswordNewScreenState extends State<ResetPasswordNewScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  // True when phase 2 was never armed with a token (deep-link straight to
  // this screen, or provider state lost): route back to the email step
  // without firing a doomed request.
  bool _missingToken = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();

    final token = auth.resetToken;
    if (token == null || token.isEmpty) {
      setState(() => _missingToken = true);
      return;
    }
    setState(() => _missingToken = false);

    final success = await auth.resetPassword(
        widget.email, token, _newPasswordController.text);

    if (!mounted) return;

    if (auth.error != null || !success) {
      // The stored verification may have lapsed (or never existed if the
      // user deep-linked here): route them back to the email step with a
      // clear message instead of looping or silently retrying.
      setState(() {});
      return;
    }

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
                _buildNewPasswordCard(auth, l10n),
                const SizedBox(height: AppSpacing.lg),
                _buildFooterLink(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewPasswordCard(AuthProvider auth, AppLocalizations l10n) {
    // A 401 means the held token is dead (or was never armed): explain the
    // restart instead of looping. Any other failure (e.g. network) surfaces
    // the raw error with a retry.
    final isVerificationFailure =
        _missingToken || auth.lastErrorStatusCode == 401;
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

          // Server Error Banner (e.g. token expired / never armed)
          if (auth.error != null || _missingToken) ...[
            ThemedErrorBanner(
              key: const Key('reset_password_error_banner'),
              message: isVerificationFailure
                  ? l10n.resetSessionExpiredMsg
                  : auth.error!,
              onRetry: isVerificationFailure ? null : _submitReset,
            ),
            const SizedBox(height: AppSpacing.md),
            // Expired-session recovery (audit A5): the banner explains the
            // restart, this button performs it — pushing a fresh email step
            // and clearing the dead code/new-password screens off the stack
            // instead of stranding the user with no next action.
            if (isVerificationFailure) ...[
              SecondaryButton(
                key: const Key('reset_back_to_email_button'),
                text: l10n.resetBackToEmailStep,
                icon: Icons.arrow_back,
                isOutlined: true,
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],

          // New Password Field
          ThemedTextField(
            key: const Key('reset_new_password_field'),
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
            key: const Key('reset_confirm_password_field'),
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
            key: const Key('submit_new_password_button'),
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
          l10n.newPasswordSubtitle,
          style: AppTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Audit A6: step-specific Back link — pop() from screen 3 lands on the
  // code step, so the label says so. The "Sign In" copy lives only on
  // screen 1, the one place pop() actually returns to Login.
  Widget _buildFooterLink(AppLocalizations l10n) {
    return Center(
      child: InkWell(
        key: const Key('reset_new_back_link'),
        onTap: () => Navigator.of(context).pop(),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_back,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.resetBackToCodeStep,
                style: AppTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
