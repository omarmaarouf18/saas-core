import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_text_field.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  final String? devOtp;

  const OtpScreen({super.key, required this.email, this.devOtp});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  String? _currentDevOtp;

  @override
  void initState() {
    super.initState();
    _currentDevOtp = widget.devOtp;
    // Auto-populate dev OTP in local development mode
    if (_currentDevOtp != null) {
      _otpController.text = _currentDevOtp!;
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resendCode() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final newDevOtp = await auth.resendOtp(widget.email);

    if (!mounted) return;

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
          content: Text("A new OTP code has been sent successfully."),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() {
        _currentDevOtp = newDevOtp;
        if (newDevOtp != null) {
          _otpController.text = newDevOtp;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final otp = _otpController.text.trim();

    final success = await auth.verifyOtp(widget.email, otp);

    if (!mounted) return;

    if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: AppColors.error,
        ),
      );
    } else if (success) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
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
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onBackground),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                    "Two-Factor Auth",
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    "Enter the 6-digit code sent to:\n${widget.email}",
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
                          controller: _otpController,
                          labelText: "6-Digit Code",
                          hintText: "000000",
                          prefixIcon: const Icon(Icons.pin_outlined),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          counterText: "",
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLgMobile.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return "Please enter the OTP";
                            }
                            if (val.trim().length != 6) {
                              return "OTP must be exactly 6 digits";
                            }
                            return null;
                          },
                        ),
                        if (_currentDevOtp != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.1),
                              border: Border.all(
                                color:
                                    AppColors.secondary.withValues(alpha: 0.4),
                              ),
                              borderRadius: AppRadius.defaultBorder,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bug_report_outlined,
                                    color: AppColors.warning),
                                const SizedBox(width: AppSpacing.base),
                                Expanded(
                                  child: Text(
                                    "Dev Mode: Auto-populated OTP '$_currentDevOtp' from response.",
                                    style: AppTypography.labelMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(
                          text: "VERIFY OTP",
                          isLoading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: auth.isLoading ? null : _resendCode,
                          child: Text(
                            "Resend Code",
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
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
