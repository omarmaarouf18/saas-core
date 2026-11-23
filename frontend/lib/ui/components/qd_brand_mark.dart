import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Palette variants for [QdBrandMark] (ADR-0029 §5, §6).
enum QdBrandMarkVariant {
  /// Ink body, Nile tail, Sun beak (standard mark for light surfaces).
  full,

  /// White body, Nile Light tail, Sun beak (for dark surfaces like Ink).
  onDark,

  /// Single color mark (follows passed color or IconTheme).
  mono,
}

/// The official Waddify brand mark (ADR-0029): a pigeon diving at a fixed 55°
/// toward the bottom left. The W shape forms the wings, the head sits in the
/// inner notch, and the tail rises from the outer point.
///
/// Drawn via [CustomPainter] from docs/design/waddify/mark.svg without any
/// external svg packages. Never rotate, mirror, or flip in RTL.
class QdBrandMark extends StatelessWidget {
  const QdBrandMark({
    super.key,
    required this.size,
    this.variant = QdBrandMarkVariant.full,
    this.color,
  });

  /// The width and height of the bounding square in logical pixels.
  final double size;

  /// Palette variant: [QdBrandMarkVariant.full], [QdBrandMarkVariant.onDark],
  /// or [QdBrandMarkVariant.mono].
  final QdBrandMarkVariant variant;

  /// Custom color override for [QdBrandMarkVariant.mono]. When omitted, falls
  /// back to [IconTheme.of(context).color] or Ink (#10233F).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? const Color(0xFF10233F);

    return Semantics(
      label: 'Waddify',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _QdBrandMarkPainter(
            variant: variant,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }
}

class _QdBrandMarkPainter extends CustomPainter {
  const _QdBrandMarkPainter({
    required this.variant,
    required this.color,
  });

  final QdBrandMarkVariant variant;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final bool isSmall = s < 48;
    final bool showTail = s >= 24;
    final bool showBeak = s >= 48 && variant != QdBrandMarkVariant.mono;

    // Determine colors per variant and size
    Color bodyColor;
    Color tailColor;
    Color beakColor;

    switch (variant) {
      case QdBrandMarkVariant.full:
        if (isSmall) {
          bodyColor = const Color(0xFF10233F); // Ink
          tailColor = const Color(0xFF10233F);
          beakColor = const Color(0xFF10233F);
        } else {
          bodyColor = const Color(0xFF10233F); // Ink
          tailColor = const Color(0xFF0E7C7B); // Nile
          beakColor = const Color(0xFFF2A541); // Sun
        }
        break;
      case QdBrandMarkVariant.onDark:
        if (isSmall) {
          bodyColor = const Color(0xFFFFFFFF); // White
          tailColor = const Color(0xFFFFFFFF);
          beakColor = const Color(0xFFFFFFFF);
        } else {
          bodyColor = const Color(0xFFFFFFFF); // White
          tailColor = const Color(0xFF2FB5B3); // Nile Light
          beakColor = const Color(0xFFF2A541); // Sun
        }
        break;
      case QdBrandMarkVariant.mono:
        bodyColor = color;
        tailColor = color;
        beakColor = color;
        break;
    }

    canvas.save();
    if (size.width != size.height) {
      canvas.translate((size.width - s) / 2.0, (size.height - s) / 2.0);
    }
    canvas.scale(s / 120.0, s / 120.0);

    // Transform from docs/design/waddify/mark.svg:
    // translate(58 62) scale(0.92) rotate(55) translate(-60 -52)
    canvas.translate(58.0, 62.0);
    canvas.scale(0.92, 0.92);
    canvas.rotate(55.0 * math.pi / 180.0);
    canvas.translate(-60.0, -52.0);

    final paint = Paint()..style = PaintingStyle.fill;

    // 1. Tail (M54 50 L 50 15 Q 60 9 70 15 L 66 50 Z)
    if (showTail) {
      paint.color = tailColor;
      final tail = Path()
        ..moveTo(54, 50)
        ..lineTo(50, 15)
        ..quadraticBezierTo(60, 9, 70, 15)
        ..lineTo(66, 50)
        ..close();
      canvas.drawPath(tail, paint);
    }

    // 2. Wings (M6 28 Q 22 88 48 68 Q 60 60 72 68 Q 98 88 114 28 Q 94 62 72 50 Q 60 44 48 50 Q 26 62 6 28 Z)
    paint.color = bodyColor;
    final wings = Path()
      ..moveTo(6, 28)
      ..quadraticBezierTo(22, 88, 48, 68)
      ..quadraticBezierTo(60, 60, 72, 68)
      ..quadraticBezierTo(98, 88, 114, 28)
      ..quadraticBezierTo(94, 62, 72, 50)
      ..quadraticBezierTo(60, 44, 48, 50)
      ..quadraticBezierTo(26, 62, 6, 28)
      ..close();
    canvas.drawPath(wings, paint);

    // 3. Head (circle cx=60 cy=74 r=9 in mark.svg, r=10 in mark-mono.svg)
    final double headRadius = isSmall ? 10.0 : 9.0;
    canvas.drawCircle(const Offset(60, 74), headRadius, paint);

    // 4. Beak (M55 81 L 60 92 L 65 81 Z)
    if (showBeak) {
      paint.color = beakColor;
      final beak = Path()
        ..moveTo(55, 81)
        ..lineTo(60, 92)
        ..lineTo(65, 81)
        ..close();
      canvas.drawPath(beak, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _QdBrandMarkPainter oldDelegate) {
    return oldDelegate.variant != variant || oldDelegate.color != color;
  }
}
