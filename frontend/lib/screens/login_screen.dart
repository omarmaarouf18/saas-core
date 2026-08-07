import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_text_field.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: AppColors.error,
        ),
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

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
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
                  // Header Row with compact QD Logotype & Pre-Login Theme/Lang Toggles
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        key: const Key('login_qd_logo'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.storefront,
                              color: AppColors.secondary,
                              size: 20,
                            ),
                            SizedBox(width: AppSpacing.xs),
                            Text(
                              "QD",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.onPrimary,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                            tooltip: "Toggle Theme Mode",
                            onPressed: () {
                              final nextMode = themeProvider.themeMode ==
                                      ThemeMode.light
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
                            tooltip: "Toggle Language",
                            onPressed: () {
                              final isAr =
                                  localeProvider?.locale?.languageCode == 'ar';
                              localeProvider?.setLocale(isAr
                                  ? const Locale('en')
                                  : const Locale('ar'));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ThemedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ThemedTextField(
                          controller: _emailController,
                          labelText: l10n.loginEmailLabel,
                          hintText: l10n.loginEmailHint,
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return l10n.loginEmailReq;
                            }
                            if (!val.contains("@")) {
                              return l10n.loginEmailInvalid;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          controller: _passwordController,
                          labelText: l10n.loginPasswordLabel,
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
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Text(
                              l10n.loginForgotPassword,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PrimaryButton(
                          text: l10n.loginSubmitButton,
                          isLoading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SignupScreen(),
                              ),
                            );
                          },
                          child: Text(
                            "${l10n.loginNoAccount} ${l10n.loginSignUp}",
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
