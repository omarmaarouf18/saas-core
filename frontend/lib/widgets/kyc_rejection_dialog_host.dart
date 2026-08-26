import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import 'info_alert_dialog.dart';

/// ADR-0021: listens for KYC/KYE rejection outcome notifications arriving via
/// SSE while the app is active and presents an immediate informational dialog
/// carrying the rejection reason, so the reviewed user does not have to hunt
/// for why they were rejected. The notification also appears normally in the
/// notifications list/badge. Only the targeted user ([NotificationModel.userId]
/// matching the signed-in user) sees the popup; other tenant members connected
/// to the same tenant-scoped SSE channel see the list entry only.
///
/// Mount below [MaterialApp] (e.g. via `builder:`) so localized strings and
/// the navigator are available when the dialog is shown.
class KycRejectionDialogHost extends StatefulWidget {
  final Widget? child;

  /// Navigator used to surface the dialog. Defaults to walking up from this
  /// widget's context; pass the app root navigator key when mounted above the
  /// Navigator (MaterialApp.builder).
  final GlobalKey<NavigatorState>? navigatorKey;

  const KycRejectionDialogHost({super.key, this.child, this.navigatorKey});

  @override
  State<KycRejectionDialogHost> createState() => _KycRejectionDialogHostState();
}

class _KycRejectionDialogHostState extends State<KycRejectionDialogHost> {
  StreamSubscription<NotificationModel>? _sub;
  String? _subscribedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthProvider>(context);
    final notifications = Provider.of<NotificationsProvider>(context);

    final userId = auth.isAuthenticated ? auth.user?.id : null;
    if (userId != null && userId.isNotEmpty) {
      // Resubscribe when the signed-in user changes; subscribe once otherwise.
      if (_sub == null || _subscribedUserId != userId) {
        _sub?.cancel();
        _sub = notifications.kycRejectionStream.listen(
          (notif) => _handleRejection(userId, notif),
        );
        _subscribedUserId = userId;
      }
    } else {
      _sub?.cancel();
      _sub = null;
      _subscribedUserId = null;
    }
  }

  void _handleRejection(String currentUserId, NotificationModel notif) {
    if (notif.userId == null || notif.userId != currentUserId) return;

    final BuildContext dialogContext =
        widget.navigatorKey?.currentContext ?? context;
    if (!dialogContext.mounted) return;
    final l10n = AppLocalizations.of(dialogContext);
    if (l10n == null) return;

    InfoAlertDialog.show(
      dialogContext,
      title: l10n.kycRejectedDialogTitle,
      message: notif.body,
      ackLabel: l10n.close,
      icon: Icons.warning_amber_rounded,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}
