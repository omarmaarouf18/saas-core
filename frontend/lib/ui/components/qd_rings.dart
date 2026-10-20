import 'package:flutter/material.dart';

import '../tokens.dart';

/// Three concentric gold discs around an icon (A-Searching "looking for a
/// courier"). Static, decorative: excluded from semantics, the state title
/// next to it says what is happening.
class QdRings extends StatelessWidget {
  const QdRings({super.key, this.icon = Icons.search, this.size = 112});

  final IconData icon;

  /// Outer diameter; the inner discs keep the mockup proportions
  /// (112 / 76 / 44).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    Widget disc(double d, Color color, Widget? child) => Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: child,
        );
    return ExcludeSemantics(
      child: disc(
        size,
        c.goldTint,
        disc(
          size * 76 / 112,
          Color.lerp(c.goldTint, c.gold, 0.5)!,
          disc(
            size * 44 / 112,
            c.gold,
            Icon(icon, size: size * 22 / 112, color: c.onGold),
          ),
        ),
      ),
    );
  }
}
