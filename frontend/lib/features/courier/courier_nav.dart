import 'package:flutter/material.dart';

import '../../screens/kyc_document_upload_screen.dart';
import '../../ui/qd_ui.dart';
import '../account/account_nav.dart';
import '../account/notifications/notifications_page.dart';
import '../account/support/tickets_page.dart';

/// Navigation out of the redesigned courier pages (FE-COURIER). Swappable
/// through [CourierNavScope] for tests.
class CourierNav {
  const CourierNav();

  /// Pushes a redesigned courier page.
  Future<T?> push<T>(BuildContext context, WidgetBuilder page) =>
      Navigator.of(context).push<T>(qdPageRoute<T>(page));

  /// Document upload for verification (KYE): the existing screen, as the
  /// old courier app's verification button opened it.
  Future<void> openVerification(BuildContext context) =>
      Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const KycDocumentUploadScreen()));

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
