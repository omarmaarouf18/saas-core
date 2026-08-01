import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
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
                  const Icon(
                    Icons.storefront_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Quick Delivery",
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    "Log in to manage your services",
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ThemedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ThemedTextField(
                          controller: _emailController,
                          labelText: "Email Address",
                          hintText: "Enter your email address",
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return "Please enter an email";
                            }
                            if (!val.contains("@")) {
                              return "Invalid email address";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          controller: _passwordController,
                          labelText: "Password",
                          hintText: "Enter your password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          obscureText: true,
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return "Please enter a password";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
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
                              "Forgot password?",
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        PrimaryButton(
                          text: "LOG IN",
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
                            "Don't have an account? Register",
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
