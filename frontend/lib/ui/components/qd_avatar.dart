import 'package:flutter/material.dart';

import '../tokens.dart';

/// Circle with the first letter of [name]. [emphasis] (default) is the
/// navy circle with a gold letter used for "your courier" / your account;
/// otherwise a muted circle for lists of people. Decorative: excluded from
/// semantics, the name is always shown next to it.
class QdAvatarInitial extends StatelessWidget {
  const QdAvatarInitial({
    super.key,
    required this.name,
    this.size = 48,
    this.emphasis = true,
    this.dimmed = false,
  });

  final String name;
  final double size;
  final bool emphasis;

  /// Frozen courier in the team list.
  final bool dimmed;

  /// First user-perceived character, upper-cased for Latin; empty for a
  /// blank name.
  static String initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final (bg, fg) = emphasis
        ? (c.navy, c.onNavy)
        : dimmed
            ? (c.border, c.textSecondary)
            : (c.fillMuted, c.textPrimary);
    final initial = initialOf(name);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: initial.isEmpty
            ? Icon(Icons.person_outline, size: size * 0.5, color: fg)
            : Text(
                initial,
                style: QdText.body.copyWith(
                  color: fg,
                  fontSize: (size * 0.375).roundToDouble(),
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
      ),
    );
  }
}

/// Section title with an optional action link ("Team now · All").
/// [small] is the 13 semibold grey label above a settings group.
class QdSectionHeader extends StatelessWidget {
  const QdSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.small = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final titleStyle = small
        ? QdText.secondary
            .copyWith(color: c.textSecondary, fontWeight: FontWeight.w600)
        : QdText.rowTitle
            .copyWith(color: c.textPrimary, fontWeight: FontWeight.w700);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: titleStyle),
          ),
        ),
        if (actionLabel != null)
          Semantics(
            button: true,
            label: actionLabel,
            excludeSemantics: true,
            onTap: onAction,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(QdRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minHeight: QdSize.minTouch, minWidth: QdSize.minTouch),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: QdSpace.x1),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      actionLabel!,
                      style: QdText.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
