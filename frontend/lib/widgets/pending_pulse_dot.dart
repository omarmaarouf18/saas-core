import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Lightweight animated "work is happening" dot for unbounded background
/// waits (audit C9, UX_PATTERNS Rule 7): dispatch searching for a courier,
/// polling, reconnect. A single implicit-style loop — no new dependencies,
/// no custom painters.
///
/// Shared root-cause fix: job_status, customer_jobs, and customer_job_map
/// all rendered static text for the same pending-dispatch wait. They now
/// share this one widget so the signal looks identical everywhere and a
/// screen built later inherits it instead of inventing a fourth variant.
///
/// The animation loops forever by design (like SkeletonLoader shimmer):
/// widget tests pumping a screen that shows this dot must use fixed
/// pumps, never pumpAndSettle, or settle will time out.
class PendingPulseDot extends StatefulWidget {
  final double size;
  final Color? color;

  const PendingPulseDot({
    super.key,
    this.size = 8,
    this.color,
  });

  @override
  State<PendingPulseDot> createState() => _PendingPulseDotState();
}

class _PendingPulseDotState extends State<PendingPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.durationSlow,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.25).animate(
        CurvedAnimation(
          parent: _controller,
          curve: AppMotion.curveStateChange,
        ),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
