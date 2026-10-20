import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../screens/home_screen.dart';
import 'login_page.dart';

/// Launch router for the redesigned signed-out flow (QD_REDESIGN_AUTH).
///
/// Like main.dart's AuthGate it shows [splash] only while the stored session
/// is restored (AuthProvider.isRestoringSession), then the home screen or
/// [LoginPage]. AuthProvider.isLoading is also true during every sign-in
/// request; keying the splash off it would unmount the sign-in page
/// mid-request, so a sign-in that needs a code would never reach the code
/// page (HOTFIX-LOGIN).
class RedesignAuthGate extends StatelessWidget {
  const RedesignAuthGate({super.key, required this.splash});

  final Widget splash;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoringSession) return splash;
    return auth.isAuthenticated ? const HomeScreen() : const LoginPage();
  }
}
