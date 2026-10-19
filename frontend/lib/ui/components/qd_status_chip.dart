import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../tokens.dart';

enum QdTone { success, warning, danger, neutral }

/// Pill chip: 12 semibold text on a tone fill. Never wraps.
class QdStatusChip extends StatelessWidget {
  const QdStatusChip({super.key, required this.label, required this.tone});

  final String label;
  final QdTone tone;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final (fg, bg) = switch (tone) {
      QdTone.success => (c.success, c.successBg),
      QdTone.warning => (c.warning, c.warningBg),
      QdTone.danger => (c.danger, c.dangerBg),
      QdTone.neutral => (c.neutral, c.neutralBg),
    };
    return Container(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(QdRadius.pill),
      ),
      child: Text(
        label,
        style: QdText.chip.copyWith(color: fg),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Every job state the redesigned screens can show, with its chip tone and
/// ARB label. The ONE place that maps backend job statuses to chips.
enum QdJobStatus {
  pending(QdTone.warning),
  pendingDispatch(QdTone.warning),
  unavailable(QdTone.danger),
  awaitingPrice(QdTone.warning),
  assigned(QdTone.success),
  active(QdTone.success),
  completed(QdTone.neutral),
  cancelled(QdTone.danger),
  underReview(QdTone.warning),

  /// Not a backend status: `cancellation_request_status == "pending"`.
  cancellationRequested(QdTone.warning),
  unknown(QdTone.neutral);

  const QdJobStatus(this.tone);

  final QdTone tone;

  String label(AppLocalizations l10n) => switch (this) {
        QdJobStatus.pending => l10n.qdStatusPending,
        QdJobStatus.pendingDispatch => l10n.qdStatusPendingDispatch,
        QdJobStatus.unavailable => l10n.qdStatusUnavailable,
        QdJobStatus.awaitingPrice => l10n.qdStatusAwaitingPrice,
        QdJobStatus.assigned => l10n.qdStatusAssigned,
        QdJobStatus.active => l10n.qdStatusActive,
        QdJobStatus.completed => l10n.qdStatusCompleted,
        QdJobStatus.cancelled => l10n.qdStatusCancelled,
        QdJobStatus.underReview => l10n.qdStatusUnderReview,
        QdJobStatus.cancellationRequested => l10n.qdStatusCancellationRequested,
        QdJobStatus.unknown => l10n.qdStatusUnknown,
      };

  /// Maps a backend `status` string. Case and surrounding space are
  /// ignored; anything unrecognised (or null) is [unknown], never a throw.
  static QdJobStatus fromBackend(String? status) =>
      switch (status?.trim().toLowerCase()) {
        'pending' => QdJobStatus.pending,
        'pending_dispatch' => QdJobStatus.pendingDispatch,
        'unavailable' => QdJobStatus.unavailable,
        'awaiting_price_response' => QdJobStatus.awaitingPrice,
        'assigned' => QdJobStatus.assigned,
        'active' => QdJobStatus.active,
        'completed' => QdJobStatus.completed,
        'cancelled' || 'canceled' => QdJobStatus.cancelled,
        'escrow_reconciliation_required' ||
        'reconciliation_required' =>
          QdJobStatus.underReview,
        _ => QdJobStatus.unknown,
      };
}

/// The chips for one job: its status, then a separate warning chip when a
/// courier's cancellation request is waiting for the owner.
List<QdJobStatus> qdJobStatusChips(
  String? status, {
  String? cancellationRequestStatus,
}) {
  return [
    QdJobStatus.fromBackend(status),
    if (cancellationRequestStatus?.trim().toLowerCase() == 'pending')
      QdJobStatus.cancellationRequested,
  ];
}

/// Renders [qdJobStatusChips] for a job.
class QdJobStatusChips extends StatelessWidget {
  const QdJobStatusChips({
    super.key,
    required this.status,
    this.cancellationRequestStatus,
  });

  final String? status;
  final String? cancellationRequestStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in qdJobStatusChips(status,
            cancellationRequestStatus: cancellationRequestStatus))
          QdStatusChip(label: s.label(l10n), tone: s.tone),
      ],
    );
  }
}
