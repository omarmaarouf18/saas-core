import '../../../models/job.dart';

/// Order timeline, phase and ETA from job model v2 (ADR-0028 §2.3 – §2.5),
/// shared by the customer order page and the owner order pages. Pure: the
/// widgets only localize what these return.
///
/// Legacy jobs (no `status_history`, ADR-0028 §2.9.4: no synthetic
/// entries) get null from [buildJobTimeline]; the pages keep their
/// `created_at`-only timeline for them.

enum JobStepKind {
  /// The booking (the first history entry).
  requested,

  /// A courier accepted (first `active` or `awaiting_price_response` after
  /// the last dispatch entry).
  accepted,

  /// The courier marked the pickup (`sub_status: picked_up`).
  pickedUp,

  /// The courier marked it delivered (`completed`, or a delivery that went
  /// to `escrow_reconciliation_required`).
  delivered,

  /// Ended: `cancelled`.
  cancelled,

  /// Ended: no courier took it (`unavailable`).
  unavailable,
}

enum JobStepState { done, current, upcoming }

class JobStep {
  const JobStep(this.kind, this.state, [this.at]);

  final JobStepKind kind;
  final JobStepState state;

  /// When the step happened; null when it has not or the history has no
  /// entry for it.
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is JobStep &&
      other.kind == kind &&
      other.state == state &&
      other.at == at;

  @override
  int get hashCode => Object.hash(kind, state, at);

  @override
  String toString() => 'JobStep($kind, $state, $at)';
}

String _n(String? s) => s?.trim().toLowerCase() ?? '';

const _dispatch = {'pending', 'pending_dispatch'};
const _accepted = {'active', 'awaiting_price_response'};
const _delivered = {
  'completed',
  'escrow_reconciliation_required',
  'reconciliation_required'
};
const _cancelled = {'cancelled', 'canceled'};

/// The timeline of [job] from its `status_history`, or null for a legacy
/// job without one.
///
/// Steps: requested → accepted → picked up → delivered; a cancelled or
/// unavailable job ends with that step instead and drops the steps it
/// never reached. A re-dispatch (back to `pending_dispatch` after a
/// courier) restarts "accepted" from the new courier. The first step not
/// reached is current, the rest upcoming.
List<JobStep>? buildJobTimeline(Job job) {
  final h = [...job.statusHistory]..sort((a, b) => a.at.compareTo(b.at));
  if (h.isEmpty) return null;

  final requested = h.first.at;
  // The last dispatch entry starts the current courier's part.
  var from = 0;
  for (var i = 0; i < h.length; i++) {
    if (_dispatch.contains(_n(h[i].status))) from = i;
  }
  DateTime? accepted, pickedUp, delivered, ended;
  JobStepKind? endKind;
  for (final e in h.skip(from)) {
    final s = _n(e.status);
    if (accepted == null && _accepted.contains(s)) accepted = e.at;
    if (_n(e.subStatus) == 'picked_up') pickedUp ??= e.at;
    if (delivered == null && _delivered.contains(s)) delivered = e.at;
    if (_cancelled.contains(s)) {
      ended = e.at;
      endKind = JobStepKind.cancelled;
    } else if (s == 'unavailable') {
      ended = e.at;
      endKind = JobStepKind.unavailable;
    }
  }

  final status = _n(job.status);
  final isEnded = _cancelled.contains(status) || status == 'unavailable';
  if (isEnded) {
    endKind ??= status == 'unavailable'
        ? JobStepKind.unavailable
        : JobStepKind.cancelled;
    return [
      JobStep(JobStepKind.requested, JobStepState.done, requested),
      if (accepted != null)
        JobStep(JobStepKind.accepted, JobStepState.done, accepted),
      if (pickedUp != null)
        JobStep(JobStepKind.pickedUp, JobStepState.done, pickedUp),
      JobStep(endKind, JobStepState.done, ended),
    ];
  }

  // What the current status says was reached, even when the history has
  // no entry for it (no time then).
  final finished = _delivered.contains(status);
  final reachedAccepted = accepted != null ||
      finished ||
      _accepted.contains(status) ||
      status == 'assigned';
  final reachedPickup =
      pickedUp != null || finished || _n(job.subStatus) == 'picked_up';
  final reached = [true, reachedAccepted, reachedPickup, finished];
  final times = [requested, accepted, pickedUp, delivered];
  const kinds = [
    JobStepKind.requested,
    JobStepKind.accepted,
    JobStepKind.pickedUp,
    JobStepKind.delivered,
  ];
  final firstOpen = reached.indexOf(false);
  return [
    for (var i = 0; i < kinds.length; i++)
      JobStep(
        kinds[i],
        reached[i]
            ? JobStepState.done
            : i == firstOpen
                ? JobStepState.current
                : JobStepState.upcoming,
        reached[i] ? times[i] : null,
      ),
  ];
}

/// The running phase of an active job (ADR-0028 §2.4).
enum JobPhase {
  /// Accepted, driving to the pickup.
  headingToPickup,

  /// Picked up, driving to the drop-off.
  pickedUp,

  /// Active without a (known) sub_status: legacy, shown as plain "active".
  unknown,
}

/// The phase of [job], or null when it is not active.
JobPhase? jobPhase(Job job) {
  final s = _n(job.status);
  if (s != 'active' && s != 'assigned') return null;
  return switch (_n(job.subStatus)) {
    'heading_to_pickup' => JobPhase.headingToPickup,
    'picked_up' => JobPhase.pickedUp,
    _ => JobPhase.unknown,
  };
}

/// The ETA of an active job: `estimated_duration_minutes` after the
/// history entry of the current phase, which is when the server computed
/// it (accept → to the pickup; pickup → to the drop-off). Null when the
/// job is not in a known phase, has no estimate, or no entry for the
/// phase.
DateTime? jobEta(Job job) {
  final minutes = job.estimatedDurationMinutes;
  final phase = jobPhase(job);
  if (minutes == null || minutes < 0 || phase == null) return null;
  final sub = switch (phase) {
    JobPhase.headingToPickup => 'heading_to_pickup',
    JobPhase.pickedUp => 'picked_up',
    JobPhase.unknown => null,
  };
  if (sub == null) return null;
  DateTime? at;
  for (final e in job.statusHistory) {
    if (_n(e.status) == 'active' && _n(e.subStatus) == sub) {
      if (at == null || e.at.isAfter(at)) at = e.at;
    }
  }
  return at?.add(Duration(minutes: minutes));
}

/// When the courier marked [job] delivered, from its history (the first
/// `completed` entry); null for legacy jobs.
DateTime? jobCompletedAt(Job job) {
  DateTime? at;
  for (final e in job.statusHistory) {
    if (_n(e.status) == 'completed' && (at == null || e.at.isBefore(at))) {
      at = e.at;
    }
  }
  return at;
}
