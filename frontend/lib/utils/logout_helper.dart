import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../screens/login_screen.dart';

/// Helper function to perform a complete logout, unregister push notifications,
/// revoke backend JWT, clear cached state, and reset navigation to LoginScreen.
Future<void> logoutAndClearProviders(BuildContext context) async {
  final auth = Provider.of<AuthProvider>(context, listen: false);

  try {
    Provider.of<NotificationsProvider>(context, listen: false).unsubscribe();
  } catch (_) {}

  await auth.logout();

  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (context) => const LoginScreen()),
    (route) => false,
  );
}
