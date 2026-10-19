import '../models/job.dart';

/// Job lifecycle rules shared by the redesigned customer screens (FE-CUST-1).
///
/// ONE definition of "ongoing" and "finished": Home's ongoing-order card and
/// the My Orders tabs both read it, so they can never disagree. Statuses are
/// compared case-insensitively with surrounding space ignored. A status that
/// is neither (unknown, empty) is shown under past orders by the screens but
/// is not "finished" here.

const Set<String> kOngoingJobStatuses = {
  'pending',
  'pending_dispatch',
  'awaiting_price_response',
  'assigned',
  'active',
  'escrow_reconciliation_required',
  'reconciliation_required',
};

const Set<String> kFinishedJobStatuses = {
  'completed',
  'cancelled',
  'canceled',
  'unavailable',
};

String _norm(String? status) => status?.trim().toLowerCase() ?? '';

/// Whether [status] is a job that still needs something to happen.
bool isOngoingStatus(String? status) =>
    kOngoingJobStatuses.contains(_norm(status));

/// Whether [status] is a terminal job state.
bool isFinishedStatus(String? status) =>
    kFinishedJobStatuses.contains(_norm(status));

bool isOngoing(Job job) => isOngoingStatus(job.status);

bool isFinished(Job job) => isFinishedStatus(job.status);

/// Newest first by `created_at`; jobs without a timestamp go last, in their
/// original order.
List<Job> sortNewestFirst(Iterable<Job> jobs) {
  final indexed = jobs.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final ta = a.value.createdAt;
    final tb = b.value.createdAt;
    if (ta == null && tb == null) return a.key.compareTo(b.key);
    if (ta == null) return 1;
    if (tb == null) return -1;
    final byTime = tb.compareTo(ta);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}

/// The most recently created ongoing job, or null when there is none.
Job? newestOngoingJob(Iterable<Job> jobs) {
  final ongoing = sortNewestFirst(jobs.where(isOngoing));
  return ongoing.isEmpty ? null : ongoing.first;
}
