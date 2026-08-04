import 'package:flutter/material.dart';
import 'forgot_password_screen.dart';

class ResetPasswordScreen extends StatelessWidget {
  final String email;
  final String? devOtp;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.devOtp,
  });

  @override
  Widget build(BuildContext context) {
    return ForgotPasswordScreen(initialEmail: email);
  }
}
