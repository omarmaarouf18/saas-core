import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import '../account/account_nav.dart';
import '../account/notifications/notifications_page.dart';
import '../account/support/tickets_page.dart';
import '../customer/chat/chat_page.dart';
import '../customer/customer_theme.dart';
import '../verification/verification_page.dart';
import 'courier_format.dart';

/// Navigation out of the redesigned courier pages (FE-COURIER). Swappable
/// through [CourierNavScope] for tests.
class CourierNav {
  const CourierNav();

  /// Pushes a redesigned courier page.
  Future<T?> push<T>(BuildContext context, WidgetBuilder page) =>
      Navigator.of(context).push<T>(qdPageRoute<T>(page));

  /// Verification (KYE): the page shared with the owner app (FE-OWNER-2b).
  Future<void> openVerification(BuildContext context) =>
      VerificationPage.open(context);

  /// Chat with the customer on the job channel (the chat page shared with
  /// the customer app).
  Future<void> openChat(BuildContext context, Job job) {
    final l10n = context.l10n;
    return Navigator.of(context).push<void>(customerRoute(
      (_) => CustomerChatPage(
        channel: 'job:${job.id}',
        title: l10n.courChatTitle,
        subtitle: jobRefIsolated(job),
        emptyBody: l10n.courChatEmpty,
      ),
    ));
  }

  Future<void> openNotifications(BuildContext context) =>
      NotificationsPage.open(context);

  Future<void> openSupport(BuildContext context) => TicketsPage.open(context);

  Future<void> signOut(BuildContext context) =>
      AccountNavScope.of(context).signOut(context);
}

class CourierNavScope extends InheritedWidget {
  const CourierNavScope({super.key, required this.nav, required super.child});

  final CourierNav nav;

  static CourierNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CourierNavScope>()?.nav ??
      const CourierNav();

  @override
  bool updateShouldNotify(CourierNavScope oldWidget) => nav != oldWidget.nav;
}
