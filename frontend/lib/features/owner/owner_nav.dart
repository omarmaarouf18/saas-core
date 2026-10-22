import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/kyc_document_upload_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/owner_history_screen.dart';
import '../../screens/subscription_screen.dart';
import '../../screens/wallet_screen.dart';
import '../../ui/qd_ui.dart';
import 'fleet_map_page.dart';
import 'owner_controller.dart';
import 'service_setup_page.dart';

/// Navigation for the redesigned owner pages (FE-OWNER-1).
///
/// New pages are pushed with [push], which renders them under the redesign
/// theme and re-provides the shell's [OwnerDataController] (pushed routes
/// live in the navigator overlay, outside the shell's providers). Screens
/// that are not rebuilt yet (FE-OWNER-2) open as they are, with the app
/// theme. Tests swap this through [OwnerNavScope] to record hand-offs.
class OwnerNav {
  const OwnerNav();

  Future<T?> push<T>(BuildContext context, WidgetBuilder page) {
    final data = context.read<OwnerDataController>();
    return Navigator.of(context).push<T>(qdPageRoute<T>(
      (_) => ChangeNotifierProvider<OwnerDataController>.value(
        value: data,
        child: Builder(builder: page),
      ),
    ));
  }

  Future<void> _old(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => screen));

  Future<void> openNotifications(BuildContext context) =>
      _old(context, const NotificationsScreen());

  /// The existing KYB document upload screen.
  Future<void> openKyb(BuildContext context) =>
      _old(context, const KycDocumentUploadScreen());

  /// Team map (O-Fleet), with [employeeId]'s courier selected if given.
  Future<void> openFleetMap(BuildContext context, {String? employeeId}) =>
      push<void>(
          context, (_) => OwnerFleetMapPage(focusEmployeeId: employeeId));

  /// Service setup (O-Service).
  Future<void> openServiceSetup(BuildContext context) =>
      OwnerServicePage.open(context);

  Future<void> openWallet(BuildContext context) =>
      _old(context, const WalletScreen());

  Future<void> openSubscription(BuildContext context) =>
      _old(context, const SubscriptionScreen());

  /// Activity log, finished jobs and ledger (the old History tab).
  Future<void> openHistory(BuildContext context) =>
      _old(context, const OwnerHistoryScreen());
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
