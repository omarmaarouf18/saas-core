import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../screens/notifications_screen.dart';
import 'order/order_detail_page.dart';

/// Navigation out of the redesigned customer pages: the order detail
/// (FE-CUST-2 [OrderDetailPage]) and the notifications screen, which is not
/// rebuilt yet. Swappable through [CustomerNavScope] for tests.
class CustomerNav {
  const CustomerNav();

  /// Opens the order detail. After a booking, [replaceStack] drops the
  /// marketplace and booking pages so "back" returns to the shell.
  Future<void> openOrder(BuildContext context, Job job,
          {bool replaceStack = false}) =>
      OrderDetailPage.open(context, job, replaceStack: replaceStack);

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
