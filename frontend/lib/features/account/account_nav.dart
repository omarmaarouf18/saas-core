import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import '../auth/auth_nav.dart';
import 'notifications/notifications_page.dart';
import 'support/tickets_page.dart';

/// Navigation out of the redesigned account pages. Swappable through
/// [AccountNavScope] for tests.
class AccountNav {
  const AccountNav();

  /// Pushes a redesigned account page.
  Future<T?> push<T>(BuildContext context, WidgetBuilder page) =>
      Navigator.of(context).push<T>(qdPageRoute<T>(page));

  Future<void> openNotifications(BuildContext context) =>
      NotificationsPage.open(context);

  Future<void> openSupport(BuildContext context) => TicketsPage.open(context);

  /// Same steps as utils/logout_helper.dart: stop the notification stream,
  /// revoke the session, then the signed-out start screen (flag-selected).
  Future<void> signOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    try {
      context.read<NotificationsProvider>().unsubscribe();
    } catch (_) {}
    await auth.logout();
    if (!context.mounted) return;
    await AuthNavScope.of(context).goSignedOut(context);
  }
}

class AccountNavScope extends InheritedWidget {
  const AccountNavScope({super.key, required this.nav, required super.child});

  final AccountNav nav;

  static AccountNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountNavScope>()?.nav ??
      const AccountNav();

  @override
  bool updateShouldNotify(AccountNavScope oldWidget) => nav != oldWidget.nav;
}

/// Floating notice used by the account pages.
void showAccountNotice(BuildContext context, String message,
    {String? actionLabel, VoidCallback? onAction}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction),
    ));
}

/// App bar of a pushed account page (back + 18 sp title, A-Notifs).
PreferredSizeWidget accountAppBar(BuildContext context, String title,
    {List<Widget> actions = const []}) {
  final c = QdColors.of(context);
  return AppBar(
    backgroundColor: c.surface,
    surfaceTintColor: c.surface,
    elevation: 0,
    titleSpacing: 0,
    title: Text(title, style: QdText.header.copyWith(color: c.textPrimary)),
    actions: actions,
  );
}
