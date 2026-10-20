import 'package:flutter/material.dart';

import '../tokens.dart';

/// 44 dp icon button (bell, filters) with a 48 dp hit area. [round] is the
/// white circle floating over a map (back, my location). An optional
/// [badgeCount] shows an unread counter (capped at 99+).
class QdIconButton extends StatelessWidget {
  const QdIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.round = false,
    this.badgeCount = 0,
    this.loading = false,
  });

  final IconData icon;

  /// Spoken label and tooltip.
  final String label;
  final VoidCallback? onPressed;
  final bool round;
  final int badgeCount;
  final bool loading;

  static const double _size = QdSize.buttonHeightSm;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final shape = round
        ? CircleBorder(side: BorderSide(color: c.border))
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QdRadius.sm),
            side: BorderSide(color: c.border),
          );
    final enabled = onPressed != null && !loading;

    Widget glyph = loading
        ? SizedBox.square(
            dimension: QdSize.icon,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: c.textPrimary),
          )
        : Icon(icon,
            size: QdSize.icon,
            color: enabled ? c.textPrimary : c.textSecondary);

    if (badgeCount > 0) {
      glyph = Stack(
        clipBehavior: Clip.none,
        children: [
          glyph,
          PositionedDirectional(
            top: -6,
            end: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: QdSpace.x1),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.danger,
                borderRadius: BorderRadius.circular(QdRadius.pill),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: QdText.chip
                    .copyWith(color: c.surface, fontSize: 10, height: 1.2),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: badgeCount > 0 ? '$label, $badgeCount' : label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: QdSize.minTouch,
          child: Center(
            child: SizedBox.square(
              dimension: _size,
              child: Material(
                color: c.surface,
                shape: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? onPressed : null,
                  child: Center(child: glyph),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
