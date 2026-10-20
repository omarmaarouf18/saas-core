import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../screens/home_screen.dart';
import 'login_page.dart';

/// Launch router for the redesigned signed-out flow (QD_REDESIGN_AUTH).
///
/// Like main.dart's AuthGate it shows [splash] while the stored session is
/// restored, then the home screen or [LoginPage]. Unlike it, the splash is
/// shown only for that first restore: AuthProvider.isLoading is also true
/// during every sign-in request, and swapping the sign-in page for the
/// splash then would unmount it mid-request (the old gate does this, so a
/// sign-in that needs a code never reaches the code screen from the root).
class RedesignAuthGate extends StatefulWidget {
  const RedesignAuthGate({super.key, required this.splash});

  final Widget splash;

  @override
  State<RedesignAuthGate> createState() => _RedesignAuthGateState();
}

class _RedesignAuthGateState extends State<RedesignAuthGate> {
  bool _restored = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoading) _restored = true;
    if (!_restored) return widget.splash;
    return auth.isAuthenticated ? const HomeScreen() : const LoginPage();
  }
}
