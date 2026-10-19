import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';
import 'qd_button.dart';

/// Centered icon, title, body and an optional secondary action, for lists
/// with nothing in them.
class QdEmptyState extends StatelessWidget {
  const QdEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return _StateLayout(
      iconBg: c.fillMuted,
      iconColor: c.textPrimary,
      icon: icon,
      title: title,
      body: body,
      action: actionLabel == null
          ? null
          : QdButton.secondary(label: actionLabel!, onPressed: onAction),
    );
  }
}

/// Load failure with a retry button. Title and body default to the generic
/// "Something went wrong / check your connection" copy.
class QdErrorState extends StatelessWidget {
  const QdErrorState({
    super.key,
    required this.onRetry,
    this.title,
    this.body,
    this.retrying = false,
  });

  final VoidCallback onRetry;
  final String? title;
  final String? body;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final l10n = context.l10n;
    return Semantics(
      liveRegion: true,
      child: _StateLayout(
        iconBg: c.dangerBg,
        iconColor: c.danger,
        icon: Icons.error_outline,
        title: title ?? l10n.qdErrorTitle,
        body: body ?? l10n.qdErrorBody,
        action: QdButton.secondary(
          label: l10n.retry,
          onPressed: onRetry,
          loading: retrying,
          icon: Icons.refresh,
        ),
      ),
    );
  }
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: QdSpace.x6, vertical: QdSpace.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: iconColor),
            ),
          ),
          const SizedBox(height: QdSpace.x4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: QdText.rowTitle.copyWith(color: c.textPrimary),
          ),
          if (body != null) ...[
            const SizedBox(height: QdSpace.x1),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: QdText.secondary
                  .copyWith(color: c.textSecondary, height: 1.6),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: QdSpace.x5),
            action!,
          ],
        ],
      ),
    );
  }
}
