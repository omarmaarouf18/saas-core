import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
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
                  Text(
                    l10n.signupTitle,
                    style: AppTypography.headlineLg.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Text(
                    l10n.signupSubtitle,
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
                              return "Username must be at least 3 characters";
                            }
                            if (runeCount > 30) {
                              return "Username must be at most 30 characters";
                            }
                            final usernameRegex =
                                RegExp(r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$');
                            if (!usernameRegex.hasMatch(trimmed)) {
                              return "Username contains invalid characters";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ThemedTextField(
                          controller: _emailController,
                          labelText: l10n.signupEmailLabel,
                          hintText: l10n.signupEmailHint,
                          prefixIcon: const Icon(Icons.email_outlined),
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return l10n.loginEmailReq;
                            }
                            final emailRegex = RegExp(
                                r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                            if (!emailRegex.hasMatch(val.trim())) {
                              return l10n.loginEmailInvalid;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
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
                        // Account Role dropdown styled with design system tokens
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.signupRoleLabel,
                              style: AppTypography.labelLg.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.base),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedRole,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.badge_outlined),
                                filled: true,
                                fillColor: AppColors.surface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.md,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.defaultBorder,
                                  borderSide: const BorderSide(
                                    color: AppColors.outlineVariant,
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: AppRadius.defaultBorder,
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurface,
                              ),
                              items: [
                                DropdownMenuItem(
                                    value: "owner",
                                    child: Text(l10n.signupRoleOwner)),
                                DropdownMenuItem(
                                    value: "user",
                                    child: Text(l10n.signupRoleCustomer)),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedRole = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(
                          text: l10n.signupSubmitButton,
                          isLoading: auth.isLoading,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: () {
                            _debouncedNav(() {
                              Navigator.of(context).pop();
                            });
                          },
                          child: Text(
                            "${l10n.signupHasAccount} ${l10n.signupSignIn}",
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
