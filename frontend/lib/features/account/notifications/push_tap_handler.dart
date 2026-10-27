import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/notification_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/notification_tap_router.dart';
import 'notification_rules.dart';

/// Placed inside each role shell, below its [NotificationShellScope]:
/// follows a tapped push (cold start or background) with the same
/// role-checked links as the notifications list, and shows a push that
/// arrives while the app is open as a notice with a "View" action.
/// Without a [NotificationTapScope] it only shows [child].
class PushTapHandler extends StatefulWidget {
  const PushTapHandler({super.key, required this.child, this.links});

  final Widget child;

  /// Where links lead (tests); default [NotificationLinks.of] this context.
  final NotificationLinks? links;

  @override
  State<PushTapHandler> createState() => _PushTapHandlerState();
}

class _PushTapHandlerState extends State<PushTapHandler> {
  NotificationTapRouter? _router;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = NotificationTapScope.maybeOf(context);
    if (router == _router) return;
    _router?.removeListener(_schedule);
    _router = router?..addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    _router?.removeListener(_schedule);
    super.dispose();
  }

  /// Follows after the current frame (a tap can arrive mid-build, and the
  /// shell's links need a laid-out tree); asks for a frame so it runs even
  /// when nothing else is redrawing.
  void _schedule() {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _consume())
      ..ensureVisualUpdate();
  }

  NotificationLinks get _links => widget.links ?? NotificationLinks.of(context);

  void _consume() {
    final router = _router;
    if (!mounted || router == null) return;
    final role = context.read<AuthProvider>().user?.role;
    if (role == null) return; // followed once the profile is known
    final tap = router.takeTap();
    if (tap != null) _links.follow(context, notificationTarget(tap, role));
    final shown = router.takeForeground();
    if (shown != null) _showForeground(shown, role);
  }

  void _showForeground(NotificationModel n, String role) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final l10n = context.l10n;
    final target = notificationTarget(n, role);
    final (title, _) = notificationCopy(l10n, n);
    final links = _links;
    final ctx = context;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('ntf_push_foreground'),
        content: Text(title.isEmpty ? n.body : title),
        action: target == NotificationTarget.none
            ? null
            : SnackBarAction(
                label: l10n.ntfPushView,
                onPressed: () {
                  if (ctx.mounted) links.follow(ctx, target);
                },
              ),
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
