import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/notification_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import 'verification_page.dart';

/// ADR-0021: when a verification-rejected notification for the signed-in
/// user arrives on the live stream, shows the reviewer's reason in a dialog
/// right away (the notification also stays in the list). Other members of
/// the same tenant channel only get the list entry.
///
/// Same trigger as the old KycRejectionDialogHost, in the redesign: the
/// reason, what to do next, and a button to the verification page.
///
/// Mount below [MaterialApp] (its `builder:`), with the app's navigator
/// key, so the dialog has localizations and a navigator.
class VerificationRejectedHost extends StatefulWidget {
  const VerificationRejectedHost({super.key, this.child, this.navigatorKey});

  final Widget? child;

  /// Navigator that shows the dialog; defaults to the one above this
  /// widget. Pass the root navigator key when mounted above it.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<VerificationRejectedHost> createState() =>
      _VerificationRejectedHostState();
}

class _VerificationRejectedHostState extends State<VerificationRejectedHost> {
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
    final dialogContext = widget.navigatorKey?.currentContext ?? context;
    if (!dialogContext.mounted) return;
    if (AppLocalizations.of(dialogContext) == null) return;
    showVerificationRejectedDialog(dialogContext,
        reason: rejectionReason(notif.body));
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

/// The reviewer's reason in an auth-service rejection body ("Your KYB
/// verification was rejected. Reason: <reason>"); null when there is none.
String? rejectionReason(String body) {
  const marker = 'Reason:';
  final i = body.indexOf(marker);
  if (i == -1) return null;
  final reason = body.substring(i + marker.length).trim();
  return reason.isEmpty ? null : reason;
}

/// The verification-rejected dialog: the reason (or a note that there is
/// none), what to do next, close, and a button to the verification page.
Future<void> showVerificationRejectedDialog(BuildContext context,
    {String? reason}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => QdThemeScope(
      child: Builder(builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        final c = QdColors.of(ctx);
        return AlertDialog(
          key: const Key('vrf_rejected_dialog'),
          backgroundColor: c.surface,
          icon: ExcludeSemantics(
            child: Container(
              width: QdSize.iconTile,
              height: QdSize.iconTile,
              decoration: BoxDecoration(
                color: c.dangerBg,
                borderRadius: BorderRadius.circular(QdRadius.sm),
              ),
              child: Icon(Icons.block, size: QdSize.icon, color: c.danger),
            ),
          ),
          title: Text(l10n.vrfStateRejectedTitle,
              style: QdText.header.copyWith(color: c.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                reason == null
                    ? l10n.vrfRejectedNoReason
                    : l10n.vrfRejectedReason(reason),
                key: const Key('vrf_rejected_reason'),
                style: QdText.body.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: QdSpace.x2),
              Text(l10n.vrfRejectedHint,
                  style: QdText.secondary.copyWith(color: c.textSecondary)),
            ],
          ),
          actions: [
            QdButton.text(
              key: const Key('vrf_rejected_close'),
              label: l10n.acctClose,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            QdButton(
              key: const Key('vrf_rejected_open'),
              label: l10n.vrfRejectedOpen,
              small: true,
              onPressed: () {
                final nav = Navigator.of(ctx);
                nav.pop();
                VerificationPage.open(nav.context);
              },
            ),
          ],
        );
      }),
    ),
  );
}
