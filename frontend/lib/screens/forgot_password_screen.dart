import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_text_field.dart';
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
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Please enter a valid email address to receive a code."),
          backgroundColor: AppColors.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("A password reset code has been sent if an account exists."),
          backgroundColor: AppColors.success,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Password reset successfully! You can now log in with your new password."),
          backgroundColor: AppColors.success,
        ),
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

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text("Forgot / Reset Password"),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
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
                  const Icon(
                    Icons.lock_reset_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Reset Your Password",
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    "Request a 6-digit reset code, then enter the code and your new password below.",
                    style: AppTypography.bodyLg.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_currentDevOtp != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.primary),
                      ),
                      child: Text(
                        "Dev OTP Code: $_currentDevOtp",
                        style: AppTypography.bodyLg.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (auth.error != null) ...[
                    ThemedErrorBanner(message: auth.error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  ThemedCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ThemedTextField(
                          key: const Key('forgot_password_email_field'),
                          controller: _emailController,
                          labelText: "Email Address",
                          hintText: "Enter your email address",
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return "Please enter your email address";
                            }
                            if (!val.contains("@")) {
                              return "Please enter a valid email address";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SecondaryButton(
                            key: const Key('request_reset_code_button'),
                            text: "Request Reset Code",
                            icon: Icons.send_outlined,
                            isLoading: _isRequestingCode,
                            onPressed: _requestCode,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          key: const Key('forgot_password_otp_field'),
                          controller: _otpController,
                          labelText: "6-Digit Code",
                          hintText: "Enter verification code",
                          prefixIcon: const Icon(Icons.pin_outlined),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          counterText: "",
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return "Please enter the verification code";
                            }
                            if (val.trim().length != 6) {
                              return "Code must be exactly 6 digits";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          key: const Key('forgot_password_new_password_field'),
                          controller: _newPasswordController,
                          labelText: "New Password",
                          hintText: "Enter your new password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          obscureText: true,
                          isPasswordField: true,
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return "Please enter a new password";
                            }
                            if (val.length < 6) {
                              return "Password must be at least 6 characters";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          key: const Key(
                              'forgot_password_confirm_password_field'),
                          controller: _confirmPasswordController,
                          labelText: "Confirm New Password",
                          hintText: "Re-enter your new password",
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                          obscureText: true,
                          isPasswordField: true,
                          validator: (val) {
                            if (val == null || val.isEmpty) {
                              return "Please confirm your new password";
                            }
                            if (val != _newPasswordController.text) {
                              return "Passwords do not match";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(
                          key: const Key('submit_reset_password_button'),
                          text: "RESET PASSWORD",
                          isLoading: auth.isLoading,
                          onPressed: _submitReset,
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
