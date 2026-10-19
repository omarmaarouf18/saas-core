import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

enum QdButtonVariant {
  /// Gold fill, navy text. One per screen.
  primary,

  /// White fill, input-colored border, navy text.
  secondary,

  /// No fill, navy text.
  text,

  /// No fill, danger text (cancel order, log out).
  destructive,
}

/// Redesign A button. Disabled when [onPressed] is null; [loading] keeps the
/// size, shows a spinner and ignores taps.
class QdButton extends StatelessWidget {
  const QdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = QdButtonVariant.primary,
    this.loading = false,
    this.fullWidth = false,
    this.small = false,
    this.icon,
  });

  const QdButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.small = false,
    this.icon,
  }) : variant = QdButtonVariant.secondary;

  const QdButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.small = false,
    this.icon,
  }) : variant = QdButtonVariant.text;

  const QdButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.fullWidth = false,
    this.small = false,
    this.icon,
  }) : variant = QdButtonVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final QdButtonVariant variant;
  final bool loading;
  final bool fullWidth;

  /// 44 dp tall with 12 radius (inline actions such as "Reply" on a row).
  /// The tap target is still padded to 48 dp.
  final bool small;
  final IconData? icon;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final enabled = onPressed != null;

    Color fill = Colors.transparent;
    Color fg;
    BorderSide side = BorderSide.none;
    switch (variant) {
      case QdButtonVariant.primary:
        fill = enabled ? c.gold : c.disabledFill;
        fg = enabled ? c.onGold : c.neutral;
      case QdButtonVariant.secondary:
        fill = c.surface;
        fg = enabled ? c.textPrimary : c.textSecondary;
        side = BorderSide(color: enabled ? c.borderInput : c.border);
      case QdButtonVariant.text:
        fg = enabled ? c.textPrimary : c.textSecondary;
      case QdButtonVariant.destructive:
        fg = enabled ? c.danger : c.textSecondary;
    }

    final isPrimary = variant == QdButtonVariant.primary;
    final height = small ? QdSize.buttonHeightSm : QdSize.buttonHeight;
    final radius = small ? QdRadius.sm : QdRadius.button;
    final style = (small
            ? QdText.buttonSm
            : isPrimary
                ? QdText.button
                : QdText.rowTitleSm)
        .copyWith(color: fg);
    final isTextLike = variant == QdButtonVariant.text ||
        variant == QdButtonVariant.destructive;

    final labelWidget = Text(
      label,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );

    final content = loading
        ? SizedBox.square(
            dimension: QdSize.icon,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
          )
        : icon == null
            ? labelWidget
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: QdSize.icon, color: fg),
                  const SizedBox(width: QdSpace.x2),
                  Flexible(child: labelWidget),
                ],
              );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

    Widget button = Material(
      color: fill,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _enabled ? onPressed : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: isTextLike ? QdSize.minTouch : height,
            minWidth: QdSize.minTouch,
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: isTextLike ? QdSpace.x2 : QdSpace.x4,
            ),
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      ),
    );

    if (fullWidth) {
      button = SizedBox(width: double.infinity, child: button);
    }

    // Small buttons keep a 48 dp hit area around the 44 dp visual.
    if (small && !isTextLike) {
      button = Padding(
        padding: const EdgeInsets.symmetric(
            vertical: (QdSize.minTouch - QdSize.buttonHeightSm) / 2),
        child: button,
      );
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: loading ? '$label, ${context.l10n.qdLoading}' : label,
      excludeSemantics: true,
      onTap: _enabled ? onPressed : null,
      child: button,
    );
  }
}
