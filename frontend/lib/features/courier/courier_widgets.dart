import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import 'courier_nav.dart';
import 'courier_rules.dart';

/// Tab-root title row of the courier pages with the notification bell
/// (unread count) on the end.
class CourierHeader extends StatelessWidget {
  const CourierHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null)
                Text(subtitle!,
                    style: QdText.secondary.copyWith(color: c.textSecondary)),
              Text(title,
                  style: QdText.screenTitle.copyWith(color: c.textPrimary)),
            ],
          ),
        ),
        const CourierBell(),
      ],
    );
  }
}

/// Bell with the unread count; opens the notifications page.
class CourierBell extends StatelessWidget {
  const CourierBell({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationsProvider>().unreadCount;
    return QdIconButton(
      key: const Key('courier_bell'),
      icon: Icons.notifications_outlined,
      label: context.l10n.acctNotifications,
      badgeCount: unread,
      onPressed: () => CourierNavScope.of(context).openNotifications(context),
    );
  }
}

/// Verification (KYE) banner while the courier's documents are missing,
/// under review or rejected; nothing once approved. The action opens the
/// document upload (C-History).
class CourierKyeBanner extends StatelessWidget {
  const CourierKyeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = context.watch<AuthProvider>().user;
    final state = kyeStateOf(user);
    if (state == KyeState.approved) return const SizedBox.shrink();
    final reason = user?.rejectionReason?.trim();
    final (tone, message, action) = switch (state) {
      KyeState.missing => (
          QdBannerTone.warning,
          l10n.courKyeMissing,
          l10n.courKyeUpload
        ),
      KyeState.pending => (
          QdBannerTone.info,
          l10n.courKyePending,
          l10n.courKyeView
        ),
      _ => (
          QdBannerTone.danger,
          reason == null || reason.isEmpty
              ? l10n.courKyeRejectedNoReason
              : l10n.courKyeRejected(reason),
          l10n.courKyeReupload
        ),
    };
    return QdBanner(
      key: Key('courier_kye_${state.name}'),
      tone: tone,
      icon: Icons.badge_outlined,
      message: message,
      actionLabel: action,
      onAction: () => CourierNavScope.of(context).openVerification(context),
    );
  }
}

/// Floating notice used by the courier pages.
void showCourierNotice(BuildContext context, String message,
    {String? actionLabel, VoidCallback? onAction, Key? key}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: key,
      content: Text(message),
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction),
    ));
}
