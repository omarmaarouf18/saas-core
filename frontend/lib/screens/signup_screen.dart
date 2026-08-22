import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'otp_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = "owner"; // Standard default
  TextDirection? _usernameDirection;
  DateTime? _lastNavTime;

  void _debouncedNav(VoidCallback navAction) {
    final now = DateTime.now();
    if (_lastNavTime != null &&
        now.difference(_lastNavTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastNavTime = now;
    navAction();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final devOtp = await auth.signup(email, username, password, _selectedRole);
    if (!mounted) return;

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _submit,
      );
    } else {
      // On success, navigate to the OTP screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => OtpScreen(email: email, devOtp: devOtp),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final l10n = context.l10n;

    return FormScreenTemplate(
      backgroundColor: AppColors.background,
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
                // Main Stitch Signup Card
                _buildSignupFormCard(auth, l10n),
                const SizedBox(height: AppSpacing.lg),

                // External Footer Navigation Link
                _buildFooterLink(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignupFormCard(AuthProvider auth, AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 4.0,
      padding: AppSpacing.lg,
      elevation: AppElevation.shadowLevel2List,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered Brand Shipping Icon
          const Center(
            child: ThemedPanel(
                color: AppColors.primaryContainer,
                shape: BoxShape.circle,
                width: 64,
                height: 64,
                child: Center(
                  child: Icon(
                    Icons.local_shipping,
                    size: 32,
                    color: AppColors.secondary,
                  ),
                )),
          ),
          const SizedBox(height: AppSpacing.md),

          // Display Title & Operational Subtitle
          Text(
            l10n.signupTitle,
            style: AppTypography.headlineLgMobile.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.signupSubtitle,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Full Name / Username Input Field
          ThemedTextField(
            controller: _usernameController,
            labelText: l10n.signupUsernameLabel,
            hintText: l10n.signupUsernameHint,
            prefixIcon: const Icon(Icons.person_outline),
            textDirection: _usernameDirection,
            onChanged: (val) {
              if (val.isNotEmpty) {
                final firstRune = val.runes.first;
                if (firstRune >= 0x0600 && firstRune <= 0x06FF) {
                  setState(() {
                    _usernameDirection = TextDirection.rtl;
                  });
                } else {
                  setState(() {
                    _usernameDirection = TextDirection.ltr;
                  });
                }
              } else {
                setState(() {
                  _usernameDirection = null;
                });
              }
            },
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return l10n.signupUsernameReq;
              }
              final trimmed = val.trim();
              final runeCount = trimmed.runes.length;
              if (runeCount < 3) {
                return l10n.usernameTooShort;
              }
              if (runeCount > 30) {
                return l10n.usernameTooLong;
              }
              final usernameRegex = RegExp(r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$');
              if (!usernameRegex.hasMatch(trimmed)) {
                return l10n.usernameInvalidChars;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),

          // Email Input Field
          ThemedTextField(
            controller: _emailController,
            labelText: l10n.signupEmailLabel,
            hintText: l10n.signupEmailHint,
            prefixIcon: const Icon(Icons.mail_outline),
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
          const SizedBox(height: AppSpacing.md),

          // Password Input Field
          ThemedTextField(
            controller: _passwordController,
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

          // Visual Role Selector (2-Card Interactive Radio Matrix)
          Text(
            l10n.signupRoleLabel,
            style: AppTypography.labelLg.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildRoleSelector(l10n),
          const SizedBox(height: AppSpacing.lg),

          // Primary Amber Gold Create Account CTA Button
          PrimaryButton(
            text: l10n.signupSubmitButton,
            trailingIcon: Icons.arrow_forward,
            isLoading: auth.isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _buildRoleCard(
            key: const Key('signup_role_customer'),
            title: l10n.signupRoleCustomer,
            icon: Icons.person_outline,
            isSelected: _selectedRole == "user",
            onTap: () => setState(() => _selectedRole = "user"),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _buildRoleCard(
            key: const Key('signup_role_owner'),
            title: l10n.signupRoleOwner,
            icon: Icons.storefront_outlined,
            isSelected: _selectedRole == "owner",
            onTap: () => setState(() => _selectedRole = "owner"),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required Key key,
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedThemedPanel(
          duration: AppMotion.durationFast,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md,
            horizontal: AppSpacing.sm,
          ),
          color: isSelected ? AppColors.surfaceContainerLow : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color:
                    isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                size: AppIconSize.md,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                style: AppTypography.labelLg.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink(AppLocalizations l10n) {
    return Center(
      child: InkWell(
        onTap: () {
          _debouncedNav(() {
            Navigator.of(context).pop();
          });
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Text(
            "${l10n.signupHasAccount} ${l10n.signupSignIn}",
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
