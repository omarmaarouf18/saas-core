import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

/// Segmented progress bar: [total] equal segments, segments up to and
/// including [current] (0-based) filled navy.
class QdStepProgress extends StatelessWidget {
  const QdStepProgress({super.key, required this.total, required this.current})
      : assert(total > 0);

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final step = current.clamp(0, total - 1);
    return Semantics(
      label: context.l10n.qdStepProgress(step + 1, total),
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: QdSpace.x1),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? c.navy : c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum QdTimelineState { done, current, upcoming }

class QdTimelineStep {
  const QdTimelineStep({
    required this.label,
    required this.state,
    this.time,
  });

  final String label;
  final QdTimelineState state;

  /// Already formatted ("2:14 PM", "Now"); omitted when unknown.
  final String? time;
}

/// Vertical order timeline (A-Track): navy dots for done steps, a gold dot
/// with a navy ring for the current one, hollow grey dots for upcoming.
class QdTimeline extends StatelessWidget {
  const QdTimeline({super.key, required this.steps});

  final List<QdTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++)
          _row(c, l10n, steps[i], isLast: i == steps.length - 1),
      ],
    );
  }

  Widget _row(QdColors c, AppLocalizations l10n, QdTimelineStep s,
      {required bool isLast}) {
    final dot = switch (s.state) {
      QdTimelineState.done =>
        BoxDecoration(color: c.navy, shape: BoxShape.circle),
      QdTimelineState.current => BoxDecoration(
          color: c.gold,
          shape: BoxShape.circle,
          border: Border.all(color: c.navy, width: 3),
        ),
      QdTimelineState.upcoming => BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.decorative, width: 2),
        ),
    };
    final stateLabel = switch (s.state) {
      QdTimelineState.done => l10n.qdTimelineDone,
      QdTimelineState.current => l10n.qdTimelineCurrent,
      QdTimelineState.upcoming => l10n.qdTimelineUpcoming,
    };
    final isCurrent = s.state == QdTimelineState.current;
    final textStyle = QdText.body.copyWith(
      color:
          s.state == QdTimelineState.upcoming ? c.textSecondary : c.textPrimary,
      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
    );

    return Semantics(
      label: [s.label, stateLabel, if (s.time != null) s.time!].join(', '),
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: isLast ? 0 : 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 14,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(width: 14, height: 14, decoration: dot),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: s.state == QdTimelineState.done
                              ? c.navy
                              : c.border,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : QdSpace.x3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(s.label, style: textStyle)),
                      if (s.time != null) ...[
                        const SizedBox(width: QdSpace.x2),
                        Text(
                          s.time!,
                          style: QdText.body.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
