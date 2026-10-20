import 'package:flutter/material.dart';

import '../tokens.dart';

enum QdIconTileTone {
  /// Gold fill: the primary service (A-Home delivery, ongoing order).
  gold,

  /// Muted fill: every other service / company tile.
  muted,

  /// Border-colored fill with secondary text: a closed company.
  disabled,
}

/// Rounded square tile holding an icon or a one-letter initial (service
/// category tiles, company initials, order cards). Decorative: excluded from
/// semantics, the name is always shown next to it.
class QdIconTile extends StatelessWidget {
  const QdIconTile({
    super.key,
    this.icon,
    this.initial,
    this.size = QdSize.iconTile,
    this.tone = QdIconTileTone.muted,
  }) : assert(icon != null || initial != null, 'icon or initial required');

  /// Tile from the first letter of [name] (blank name → generic icon).
  factory QdIconTile.initialOf(
    String name, {
    Key? key,
    double size = QdSize.iconTile,
    QdIconTileTone tone = QdIconTileTone.muted,
  }) {
    final trimmed = name.trim();
    return QdIconTile(
      key: key,
      size: size,
      tone: tone,
      initial: trimmed.isEmpty ? null : trimmed.characters.first.toUpperCase(),
      icon: trimmed.isEmpty ? Icons.storefront_outlined : null,
    );
  }

  final IconData? icon;
  final String? initial;
  final double size;
  final QdIconTileTone tone;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final (bg, fg) = switch (tone) {
      QdIconTileTone.gold => (c.gold, c.onGold),
      QdIconTileTone.muted => (c.fillMuted, c.textPrimary),
      QdIconTileTone.disabled => (c.border, c.textSecondary),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(QdRadius.sm),
        ),
        child: initial != null
            ? Text(
                initial!,
                style: QdText.header.copyWith(
                  color: fg,
                  fontSize: (size * 0.38).roundToDouble(),
                  height: 1.2,
                ),
              )
            : Icon(
                icon,
                size: size >= QdSize.iconTileLg ? QdSize.iconLg : QdSize.icon,
                color: fg,
              ),
      ),
    );
  }
}
