import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'signup_screen.dart';
import 'otp_screen.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

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
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final devOtp = await auth.login(email, password);
    if (!mounted) return;

    if (auth.error != null) {
      ThemedSnackBar.showError(
        context,
        auth.error!,
        onRetry: _submit,
      );
    } else {
      if (auth.isAuthenticated) {
        // Employees bypass 2FA and are authenticated immediately
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        // Owners and Customers require 2FA OTP verification
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OtpScreen(email: email, devOtp: devOtp),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider?>(context);
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
                // 1. Top Chrome Bar: QD Logo & Language/Theme Toggles
                _buildTopChromeBar(themeProvider, localeProvider, l10n),
                const SizedBox(height: AppSpacing.md),

                // 2. Main Stitch Card Container
                _buildLoginFormCard(auth, l10n),
                const SizedBox(height: AppSpacing.lg),

                // 3. External Footer Navigation Link
                _buildFooterLink(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopChromeBar(
    ThemeProvider themeProvider,
    LocaleProvider? localeProvider,
    AppLocalizations l10n,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ThemedPanel(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.md),
            key: const Key('login_qd_logo'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storefront,
                  color: AppColors.secondary,
                  size: AppIconSize.md,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  "QD",
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.onPrimary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            )),
        Row(
          children: [
            IconButton(
              key: const Key('login_theme_toggle_button'),
              icon: Icon(
                themeProvider.themeMode == ThemeMode.dark
                    ? Icons.dark_mode_outlined
                    : (themeProvider.themeMode == ThemeMode.light
                        ? Icons.light_mode_outlined
                        : Icons.brightness_auto_outlined),
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: l10n.tooltipToggleTheme,
              onPressed: () {
                final nextMode = themeProvider.themeMode == ThemeMode.light
                    ? ThemeMode.dark
                    : (themeProvider.themeMode == ThemeMode.dark
                        ? ThemeMode.system
                        : ThemeMode.light);
                themeProvider.setThemeMode(nextMode);
              },
            ),
            IconButton(
              key: const Key('login_lang_toggle_button'),
              icon: Icon(
                Icons.language,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: l10n.tooltipToggleLanguage,
              onPressed: () {
                final isAr = localeProvider?.locale?.languageCode == 'ar';
                localeProvider
                    ?.setLocale(isAr ? const Locale('en') : const Locale('ar'));
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoginFormCard(AuthProvider auth, AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.lg,
      topAccentColor: AppColors.secondary,
      topAccentHeight: 4.0,
      padding: AppSpacing.lg,
      elevation: AppElevation.shadowLevel2List,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered Brand Icon
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

          // Brand Headline & Subtitle
          Text(
            l10n.loginTitle,
            style: AppTypography.headlineLgMobile.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.loginSubtitle,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Email Input Field
          ThemedTextField(
            controller: _emailController,
            labelText: l10n.loginEmailLabel,
            hintText: l10n.loginEmailHint,
            prefixIcon: const Icon(Icons.person_outline),
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

          // Password Header Row with Inline "Forgot Password?"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                l10n.loginPasswordLabel,
                style: AppTypography.labelLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              InkWell(
                onTap: () {
                  _debouncedNav(() {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordScreen(),
                      ),
                    );
                  });
                },
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xxs,
                    horizontal: AppSpacing.xs,
                  ),
                  child: Text(
                    l10n.loginForgotPassword,
                    style: AppTypography.labelLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),

          // Password Input Field
          ThemedTextField(
            controller: _passwordController,
            hintText: l10n.loginPasswordHint,
            prefixIcon: const Icon(Icons.lock_outline),
            obscureText: true,
            isPasswordField: true,
            validator: (val) {
              if (val == null || val.isEmpty) {
                return l10n.loginPasswordReq;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // Primary Amber Gold Sign In Button
          PrimaryButton(
            text: l10n.loginSubmitButton,
            trailingIcon: Icons.arrow_forward,
            isLoading: auth.isLoading,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(AppLocalizations l10n) {
    return Center(
      child: InkWell(
        onTap: () {
          _debouncedNav(() {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const SignupScreen(),
              ),
            );
          });
        },
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Text(
            "${l10n.loginNoAccount} ${l10n.loginSignUp}",
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
