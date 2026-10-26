import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'launch_splash.dart';
import 'login_page.dart';
import 'role_home.dart';

/// Launch router (UX-17): [splash] (default [LaunchSplash]) only while the
/// stored session is restored (AuthProvider.isRestoringSession), then the
/// role's home ([RoleHome]) or [LoginPage]. AuthProvider.isLoading is also
/// true during every sign-in request; keying the splash off it would
/// unmount the sign-in page mid-request, so a sign-in that needs a code
/// would never reach the code page (HOTFIX-LOGIN).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.splash = const LaunchSplash()});

  final Widget splash;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoringSession) return splash;
    return auth.isAuthenticated ? const RoleHome() : const LoginPage();
  }
}
