import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/feature_flags.dart';
import '../features/auth/auth_nav.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';

/// Helper function to perform a complete logout, unregister push notifications,
/// revoke backend JWT, clear cached state, and reset navigation to the
/// signed-out start screen ([signedOutRootScreen]: the redesigned LoginPage
/// when [redesign], default the QD_REDESIGN_AUTH flag, is on, otherwise
/// LoginScreen).
Future<void> logoutAndClearProviders(BuildContext context,
    {bool redesign = kRedesignAuth}) async {
  final auth = Provider.of<AuthProvider>(context, listen: false);

  try {
    Provider.of<NotificationsProvider>(context, listen: false).unsubscribe();
  } catch (_) {}

  await auth.logout();

  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
        builder: (context) => signedOutRootScreen(redesign: redesign)),
    (route) => false,
  );
}
