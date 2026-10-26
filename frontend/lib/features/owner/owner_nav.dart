import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../account/notifications/notifications_page.dart';
import '../account/support/tickets_page.dart';
import '../verification/verification_page.dart';
import 'activity_log_page.dart';
import 'fleet_map_page.dart';
import 'owner_controller.dart';
import 'plan_page.dart';
import 'service_setup_page.dart';
import 'wallet_page.dart';

/// Navigation for the redesigned owner pages (FE-OWNER-1).
///
/// New pages are pushed with [push], which re-provides the shell's
/// [OwnerDataController] (pushed routes live in the navigator overlay,
/// outside the shell's providers). Tests
/// swap this through [OwnerNavScope] to record hand-offs.
class OwnerNav {
  const OwnerNav();

  Future<T?> push<T>(BuildContext context, WidgetBuilder page) {
    final data = context.read<OwnerDataController>();
    return Navigator.of(context).push<T>(MaterialPageRoute<T>(
      builder: (_) => ChangeNotifierProvider<OwnerDataController>.value(
        value: data,
        child: Builder(builder: page),
      ),
    ));
  }

  /// Notifications: the page shared by every role, with owner links.
  Future<void> openNotifications(BuildContext context) =>
      NotificationsPage.open(context);

  /// Verification (KYB): the page shared with the courier app.
  Future<void> openKyb(BuildContext context) => VerificationPage.open(context);

  /// Team map (O-Fleet), with [employeeId]'s courier selected if given.
  Future<void> openFleetMap(BuildContext context, {String? employeeId}) =>
      push<void>(
          context, (_) => OwnerFleetMapPage(focusEmployeeId: employeeId));

  /// Service setup (O-Service).
  Future<void> openServiceSetup(BuildContext context) =>
      OwnerServicePage.open(context);

  /// Wallet, read-only (FE-OWNER-2b).
  Future<void> openWallet(BuildContext context) =>
      OwnerWalletPage.open(context);

  /// Plan, read-only (FE-OWNER-2b).
  Future<void> openSubscription(BuildContext context) =>
      OwnerPlanPage.open(context);

  /// Support tickets (the account page's support list).
  Future<void> openSupport(BuildContext context) => TicketsPage.open(context);

  /// Activity log: activity and money (replaces the old History tab).
  Future<void> openHistory(BuildContext context) =>
      OwnerActivityPage.open(context);
}

class OwnerNavScope extends InheritedWidget {
  const OwnerNavScope({super.key, required this.nav, required super.child});

  final OwnerNav nav;

  static OwnerNav of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OwnerNavScope>()?.nav ??
      const OwnerNav();

  @override
  bool updateShouldNotify(OwnerNavScope oldWidget) => nav != oldWidget.nav;
}
