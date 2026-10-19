import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../screens/job_status_screen.dart';
import '../../screens/notifications_screen.dart';

/// Where the redesigned customer pages hand off to screens that are not
/// rebuilt yet (order detail = the existing JobStatusScreen until FE-CUST-2,
/// notifications). Swappable through [CustomerNavScope] for tests.
class CustomerNav {
  const CustomerNav();

  /// Opens the order detail. After a booking, [replaceStack] drops the
  /// marketplace and booking pages so "back" returns to the shell.
  Future<void> openOrder(BuildContext context, Job job,
      {bool replaceStack = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => JobStatusScreen(job: job),
    );
    final nav = Navigator.of(context);
    if (replaceStack) {
      return nav.pushAndRemoveUntil(route, (r) => r.isFirst);
    }
    return nav.push(route);
  }

  Future<void> openNotifications(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const NotificationsScreen(),
      ));
}

class CustomerNavScope extends InheritedWidget {
  const CustomerNavScope({super.key, required this.nav, required super.child});

  final CustomerNav nav;

  static CustomerNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomerNavScope>()?.nav ??
      const CustomerNav();

  @override
  bool updateShouldNotify(CustomerNavScope oldWidget) => nav != oldWidget.nav;
}
