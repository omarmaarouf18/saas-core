import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/push_notification_service.dart';
import '../../../ui/qd_ui.dart';

/// Placed inside each role shell (PUSH-FCM), below a
/// [PushNotificationService] provider: once per install, a little
/// after the shell first shows (never on the launch or sign-in screens),
/// offers to turn notifications on with role-specific copy. "Turn on"
/// opens the phone's permission dialog; "Not now", or closing the sheet,
/// answers it too. Nothing is shown when push is unavailable in this
/// build, the phone was already asked, or the prompt was answered before.
class PushPermissionPrompt extends StatefulWidget {
  const PushPermissionPrompt({
    super.key,
    required this.child,
    this.delay = const Duration(seconds: 2),
  });

  final Widget child;

  /// Lets the shell's first screen settle before the sheet slides up.
  final Duration delay;

  @override
  State<PushPermissionPrompt> createState() => _PushPermissionPromptState();
}

class _PushPermissionPromptState extends State<PushPermissionPrompt> {
  PushNotificationService? _push;
  Timer? _timer;
  bool _ready = false;
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final push = context.read<PushNotificationService?>();
    if (push == _push) return;
    _push?.removeListener(_maybeShow);
    _push = push?..addListener(_maybeShow);
    // No push in this build: nothing to offer, no timer.
    if (push != null && push.available) {
      _timer ??= Timer(widget.delay, () {
        _ready = true;
        _maybeShow();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _push?.removeListener(_maybeShow);
    super.dispose();
  }

  /// Waits for the delay and for sign-in's permission read (the service
  /// notifies when it lands).
  void _maybeShow() {
    final push = _push;
    if (!mounted || !_ready || _shown || push == null) return;
    if (!push.shouldOfferPrompt) return;
    // Not over another page or dialog the user is busy with.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _shown = true;
    _show(push);
  }

  Future<void> _show(PushNotificationService push) async {
    final l10n = context.l10n;
    final role = context.read<AuthProvider>().user?.role;
    final body = switch (role) {
      'owner' => l10n.pushPromptBodyOwner,
      'employee' => l10n.pushPromptBodyCourier,
      _ => l10n.pushPromptBodyCustomer,
    };
    final turnOn = await QdBottomSheet.show<bool>(
      context,
      title: l10n.pushPromptTitle,
      subtitle: body,
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdButton(
              key: const Key('push_prompt_turn_on'),
              label: l10n.pushPromptTurnOn,
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: QdSpace.x2),
            QdButton(
              key: const Key('push_prompt_not_now'),
              label: l10n.pushPromptNotNow,
              variant: QdButtonVariant.text,
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (turnOn == true) {
      await push.requestPermission();
    } else {
      await push.markPromptAnswered();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The phone notifications row of the account page's App section, or
/// null when push is unavailable in this build (or there is no
/// [PushNotificationService] above, as in page tests). On: opens the
/// phone's settings (to manage or turn off). Off: asks the phone while it
/// still can, otherwise opens the settings.
QdListTile? pushSettingsTile(BuildContext context) {
  final push = context.read<PushNotificationService?>();
  if (push == null) return null;
  final p = push.permission;
  if (!push.available || p == PushPermission.unavailable) return null;
  final l10n = context.l10n;
  final on = p == PushPermission.granted;
  return QdListTile(
    key: const Key('account_push'),
    icon: on
        ? Icons.notifications_active_outlined
        : Icons.notifications_off_outlined,
    title: l10n.acctPushRow,
    value: on ? l10n.acctPushOn : l10n.acctPushOff,
    chevron: true,
    onTap: () async {
      if (p == PushPermission.notDetermined || p == PushPermission.denied) {
        final now = await push.requestPermission();
        if (now == PushPermission.blocked) await push.openSettings();
      } else {
        await push.openSettings();
      }
    },
  );
}

/// Under the App section when the phone refused notifications: says what
/// that means and links to the phone's settings. Shown on the account
/// page only (no nagging elsewhere).
class PushOffHint extends StatelessWidget {
  const PushOffHint({super.key});

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushNotificationService?>();
    if (push == null) return const SizedBox.shrink();
    final p = push.permission;
    if (!push.available ||
        (p != PushPermission.denied && p != PushPermission.blocked)) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: QdSpace.x2),
      child: QdBanner(
        key: const Key('account_push_off_hint'),
        tone: QdBannerTone.info,
        icon: Icons.notifications_off_outlined,
        message: l10n.acctPushOffHint,
        actionLabel: l10n.acctPushOpenSettings,
        onAction: push.openSettings,
      ),
    );
  }
}
