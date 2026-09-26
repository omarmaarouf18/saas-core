import 'package:flutter/material.dart';

/// Bounded inline busy indicator (UI visual audit 2026-09, gap G2).
///
/// Five call sites hand-rolled the same `SizedBox.square +
/// CircularProgressIndicator` in three sizes (8px connecting dot, 18px
/// refresh swaps, 20px send/attach/enable buttons) with two stroke widths.
/// `ThemedLoadingIndicator` cannot serve these bounds (it is a centered
/// full-size widget — see UX_PATTERNS.md Rule 4's size exception), so this
/// is the sanctioned small-bounds counterpart: a square box of exactly
/// [size] with a progress indicator inside.
///
/// [strokeWidth] defaults by size, codifying the existing variance:
/// hairline 1.5 at or below 12px, standard 2.0 above. [color] defaults to
/// the theme primary (the `CircularProgressIndicator` default).
class ThemedInlineSpinner extends StatelessWidget {
  /// Square box dimension in dp (e.g. 8, 18, 20 at current call sites).
  final double size;

  /// Indicator color. Null keeps the theme-primary default.
  final Color? color;

  /// Explicit stroke width override. Null applies the size rule above.
  final double? strokeWidth;

  const ThemedInlineSpinner({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth ?? (size <= 12 ? 1.5 : 2.0),
        color: color,
      ),
    );
  }
}
