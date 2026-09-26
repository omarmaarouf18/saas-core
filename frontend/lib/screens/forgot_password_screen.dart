import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'reset_password_otp_screen.dart';

// Screen 1 of the two-phase reset flow (ADR-0026): collects the account
// email and requests a verification code via the existing
// AuthProvider.forgotPassword (unchanged). On success it pushes the OTP
// screen, passing the email plus the dev-mode OTP (when the backend
// returns one) — the code itself is verified on screen 2 and never
// carried past it.
class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();

    setState(() {
      _isRequestingCode = true;
    });

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();
    final devOtp = await auth.forgotPassword(email);

    if (!mounted) return;

    setState(() {
      _isRequestingCode = false;
    });

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _requestCode,
      );
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    ThemedSnackBar.showSuccess(context, l10n.forgotPasswordSentMsg);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ResetPasswordOtpScreen(email: email, devOtp: devOtp),
      ),
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
                // Main Stitch Reset Password Card
                _buildEmailCard(auth, l10n),
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

  Widget _buildEmailCard(AuthProvider auth, AppLocalizations l10n) {
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

          // Server Error Banner
          if (auth.error != null) ...[
            ThemedErrorBanner(
              message: auth.error!,
              onRetry: _requestCode,
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
          const SizedBox(height: AppSpacing.lg),

          // Primary Send Code Action Button
          PrimaryButton(
            key: const Key('request_reset_code_button'),
            text: l10n.forgotPasswordSendCodeButton,
            trailingIcon: Icons.arrow_forward,
            isLoading: _isRequestingCode || auth.isLoading,
            onPressed: _requestCode,
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
                  size: AppIconSize.lg,
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
          l10n.forgotPasswordStep1Subtitle,
          style: AppTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
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
