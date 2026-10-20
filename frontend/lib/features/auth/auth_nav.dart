import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../screens/home_screen.dart';
import '../../screens/login_screen.dart';
import 'login_page.dart';
import 'reset_password_page.dart';

/// The signed-out start screen: the redesigned [LoginPage] when [redesign]
/// (default: the `QD_REDESIGN_AUTH` flag) is on, otherwise the existing
/// LoginScreen.
Widget signedOutRootScreen({bool redesign = kRedesignAuth}) =>
    redesign ? const LoginPage() : const LoginScreen();

/// Navigation out of the redesigned auth pages. Swappable through
/// [AuthNavScope] so tests do not build the whole signed-in app.
class AuthNav {
  const AuthNav();

  /// After a successful sign-in: the role's home screen, replacing the
  /// whole stack so back never returns to the sign-in pages (the old
  /// OtpScreen did the same).
  Future<void> goHome(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (route) => false,
      );

  /// Password reset from the sign-in page. Completes with the email the
  /// reset ended with (to prefill sign-in), or null.
  Future<String?> openPasswordReset(BuildContext context, {String? email}) =>
      Navigator.of(context).push<String>(MaterialPageRoute<String>(
        builder: (_) => ResetPasswordPage(initialEmail: email),
      ));

  /// After signing out: the signed-out start screen, replacing the stack.
  Future<void> goSignedOut(BuildContext context) =>
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => signedOutRootScreen()),
        (route) => false,
      );
}

class AuthNavScope extends InheritedWidget {
  const AuthNavScope({super.key, required this.nav, required super.child});

  final AuthNav nav;

  static AuthNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthNavScope>()?.nav ??
      const AuthNav();

  @override
  bool updateShouldNotify(AuthNavScope oldWidget) => nav != oldWidget.nav;
}
