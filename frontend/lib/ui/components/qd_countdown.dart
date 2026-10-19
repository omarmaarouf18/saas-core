import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

enum QdCountdownStyle {
  /// 72 dp gold ring with mm:ss inside (courier offer, C-Offer).
  ring,

  /// mm:ss on the end of a label row over a shrinking navy bar
  /// (price proposal, A-Negotiate).
  bar,
}

/// Time left until [expiresAt], as `mm:ss` plus a ring or bar that shrinks
/// over [total]. Calls [onExpired] once when it reaches zero (immediately on
/// first build when already expired).
class QdCountdown extends StatefulWidget {
  const QdCountdown({
    super.key,
    required this.expiresAt,
    required this.total,
    this.style = QdCountdownStyle.ring,
    this.label,
    this.onExpired,
    this.now = DateTime.now,
  });

  final DateTime expiresAt;

  /// Full window (e.g. the 30 s offer timeout); the bar or ring shows
  /// remaining / total.
  final Duration total;
  final QdCountdownStyle style;

  /// Text before the time in the bar style ("Offer expires in").
  final String? label;
  final VoidCallback? onExpired;

  /// Clock, injectable for tests.
  final DateTime Function() now;

  /// `mm:ss`, minutes zero-padded; never negative.
  static String format(Duration d) {
    final s = d.isNegative ? 0 : (d.inMilliseconds / 1000).ceil();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  State<QdCountdown> createState() => _QdCountdownState();
}

class _QdCountdownState extends State<QdCountdown> {
  Timer? _timer;
  bool _fired = false;

  Duration get _remaining {
    final r = widget.expiresAt.difference(widget.now());
    return r.isNegative ? Duration.zero : r;
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(QdCountdown old) {
    super.didUpdateWidget(old);
    if (old.expiresAt != widget.expiresAt) {
      _fired = false;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (_check()) return;
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() {});
      _check();
    });
  }

  /// Fires [QdCountdown.onExpired] once; true when expired.
  bool _check() {
    if (_remaining > Duration.zero) return false;
    _timer?.cancel();
    if (!_fired) {
      _fired = true;
      final cb = widget.onExpired;
      if (cb != null) scheduleMicrotask(cb);
    }
    return true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final remaining = _remaining;
    final totalMs = widget.total.inMilliseconds;
    final fraction = totalMs <= 0
        ? 0.0
        : (remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final text = QdCountdown.format(remaining);
    final semantics = context.l10n.qdTimeLeft(text);

    final time = Text(
      text,
      textDirection: TextDirection.ltr,
      style: (widget.style == QdCountdownStyle.ring
              ? QdText.amountLg.copyWith(fontSize: 20)
              : QdText.bodyStrong.copyWith(fontWeight: FontWeight.w700))
          .copyWith(
        color: c.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (widget.style == QdCountdownStyle.ring) {
      return Semantics(
        label: semantics,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: 72,
          child: CustomPaint(
            painter: _RingPainter(
              fraction: fraction,
              fill: c.gold,
              track: c.border,
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
            child: Center(child: time),
          ),
        ),
      );
    }

    return Semantics(
      label: widget.label == null ? semantics : '${widget.label}, $semantics',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.label != null)
                Expanded(
                  child: Text(widget.label!,
                      style: QdText.body.copyWith(color: c.textSecondary)),
                )
              else
                const Spacer(),
              time,
            ],
          ),
          const SizedBox(height: QdSpace.x2),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 6,
              color: c.border,
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.navy,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.rtl,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final bool rtl;

  static const double _stroke = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(_stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base);
    if (fraction <= 0) return;
    // Remaining time runs from 12 o'clock in the reading direction.
    final sweep = math.pi * 2 * fraction * (rtl ? -1 : 1);
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      sweep,
      false,
      base
        ..color = fill
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.track != track ||
      old.rtl != rtl;
}
