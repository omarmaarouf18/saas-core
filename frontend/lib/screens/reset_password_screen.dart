import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_text_field.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String? devOtp;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.devOtp,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String? _currentDevOtp;

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
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    auth.clearError();

    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text;

    final success = await auth.resetPassword(widget.email, otp, newPassword);

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
        title: const Text("Enter Reset Code"),
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
                    Icons.security_outlined,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    "Set New Password",
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    "Enter the 6-digit code sent to ${widget.email} along with your new password.",
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
                          controller: _otpController,
                          labelText: "6-Digit Code",
                          hintText: "Enter 6-digit verification code",
                          prefixIcon: const Icon(Icons.pin_outlined),
                          keyboardType: TextInputType.number,
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
                          controller: _newPasswordController,
                          labelText: "New Password",
                          hintText: "Enter your new password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          obscureText: true,
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
                          controller: _confirmPasswordController,
                          labelText: "Confirm New Password",
                          hintText: "Re-enter your new password",
                          prefixIcon: const Icon(Icons.lock_reset_outlined),
                          obscureText: true,
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
                          text: "UPDATE PASSWORD",
                          isLoading: auth.isLoading,
                          onPressed: _submit,
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
