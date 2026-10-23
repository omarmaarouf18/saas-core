import '../../models/job.dart';
import '../../models/user_profile.dart';

/// Courier job rules (FE-COURIER), pure and unit tested. Statuses are
/// compared case-insensitively with surrounding space ignored.

String _norm(String? s) => s?.trim().toLowerCase() ?? '';

/// Server offer window: user-service gives each courier 60 s
/// (`time.Now().Add(60 * time.Second)` when an offer advances).
const Duration kOfferWindow = Duration(seconds: 60);

/// Jobs that are over for the courier: they only appear under My jobs.
/// A job under review (reconciliation) is over for the courier too: the
/// owner decides the rest.
const Set<String> kCourierFinishedStatuses = {
  'completed',
  'cancelled',
  'canceled',
  'unavailable',
  'escrow_reconciliation_required',
  'reconciliation_required',
};

/// A dispatch offer waiting for this courier's answer (the old screen's
/// "incoming offer" card).
bool isOffer(Job job) => _norm(job.status) == 'pending_dispatch';

bool isActive(Job job) => _norm(job.status) == 'active';

bool isAwaitingPrice(Job job) => _norm(job.status) == 'awaiting_price_response';

bool isCourierFinished(Job job) =>
    kCourierFinishedStatuses.contains(_norm(job.status));

/// Assigned and still running: anything that is neither an offer nor over
/// (active, awaiting a price answer, pending, or a status this client does
/// not know, which the old screen also listed as a job card).
bool isCurrent(Job job) => !isOffer(job) && !isCourierFinished(job);

/// The offer to show: the one that expires first (no expiry last).
Job? currentOffer(Iterable<Job> jobs) {
  final offers = jobs.where(isOffer).toList();
  if (offers.isEmpty) return null;
  final far = DateTime.utc(9999);
  offers.sort(
      (a, b) => (a.offerExpiresAt ?? far).compareTo(b.offerExpiresAt ?? far));
  return offers.first;
}

/// Whether the offer's answer window is over at [now] (no expiry: over).
bool isOfferExpired(Job offer, DateTime now) {
  final expires = offer.offerExpiresAt;
  return expires == null || !expires.isAfter(now);
}

int _currentRank(Job job) {
  if (isActive(job)) return 0;
  if (isAwaitingPrice(job)) return 1;
  return 2;
}

/// The current job to show: an active one first, then one waiting for a
/// price answer, then anything else still running; newest first within a
/// rank.
Job? currentJob(Iterable<Job> jobs) {
  final current = jobs.where(isCurrent).toList();
  if (current.isEmpty) return null;
  final old = DateTime.utc(1970);
  current.sort((a, b) {
    final r = _currentRank(a).compareTo(_currentRank(b));
    if (r != 0) return r;
    return (b.updatedAt ?? b.createdAt ?? old)
        .compareTo(a.updatedAt ?? a.createdAt ?? old);
  });
  return current.first;
}

/// Running jobs besides the one shown (the old screen listed them all).
int otherCurrentCount(Iterable<Job> jobs) {
  final n = jobs.where(isCurrent).length;
  return n > 1 ? n - 1 : 0;
}

/// The availability switch is locked while a job is active (as before).
bool hasActiveJob(Iterable<Job> jobs) => jobs.any(isActive);

/// The courier's verification (KYE) state, for the banner.
enum KyeState { approved, missing, pending, rejected }

KyeState kyeStateOf(UserProfile? user) => switch (_norm(user?.kyeStatus)) {
      'approved' => KyeState.approved,
      'rejected' => KyeState.rejected,
      '' => KyeState.missing,
      _ => KyeState.pending,
    };

/// Suspended by a reviewer, or paused (frozen) by the company: the auth
/// service reports both as `account_status: suspended`.
bool isBlocked(UserProfile? user) => user?.isSuspended ?? false;

/// The one primary action of the current job (A-Courier).
enum CourierAction { none, pickup, deliver }

/// heading_to_pickup -> pickup; picked_up, or no sub-status (jobs from
/// before job model v2) -> deliver; nothing unless the job is active.
CourierAction primaryActionFor(Job job) {
  if (!isActive(job)) return CourierAction.none;
  return _norm(job.subStatus) == 'heading_to_pickup'
      ? CourierAction.pickup
      : CourierAction.deliver;
}

/// The stop the courier is heading to: the pickup until it is picked up,
/// then the drop-off (the pickup when no drop-off was set).
JobLocation navigationTarget(Job job) =>
    primaryActionFor(job) == CourierAction.pickup
        ? job.location
        : (job.destination ?? job.location);

/// A cancellation can be requested while the job runs and no request is
/// pending (the old rule).
bool canRequestCancellation(Job job) =>
    isCurrent(job) && _norm(job.cancellationRequestStatus) != 'pending';

const Set<String> _endStatuses = {
  'completed',
  'cancelled',
  'canceled',
  'unavailable',
  'escrow_reconciliation_required',
  'reconciliation_required',
};

/// When the job ended, from the server timeline (job model v2): the time
/// of the last entry with an end status. Null for older jobs with no
/// timeline.
DateTime? finishedAt(Job job) {
  for (final e in job.statusHistory.reversed) {
    if (_endStatuses.contains(_norm(e.status))) return e.at;
  }
  return null;
}

/// My jobs list: finished jobs, newest first (end time, else last update,
/// else creation).
List<Job> finishedJobs(Iterable<Job> jobs) {
  final old = DateTime.utc(1970);
  DateTime key(Job j) => finishedAt(j) ?? j.updatedAt ?? j.createdAt ?? old;
  return jobs.where(isCourierFinished).toList()
    ..sort((a, b) => key(b).compareTo(key(a)));
}

/// Today's completed jobs and the cash at their order price.
class CourierDayStats {
  const CourierDayStats(
      {required this.completed, required this.cash, required this.estimated});

  final int completed;

  /// Sum of the agreed (else suggested) price of today's completed cash
  /// orders. The amount actually collected is not sent to couriers.
  final double cash;

  /// True when a completed job has no completion time on its timeline
  /// (jobs from before job model v2), so it was counted by its creation
  /// day instead.
  final bool estimated;
}

bool _sameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

CourierDayStats todayStats(Iterable<Job> jobs, DateTime now) {
  var count = 0;
  var cash = 0.0;
  var estimated = false;
  for (final j in jobs) {
    if (_norm(j.status) != 'completed') continue;
    var when = j.historyTimeOf('completed');
    if (when == null) {
      estimated = true;
      when = j.createdAt;
    }
    if (when == null || !_sameLocalDay(when, now)) continue;
    count++;
    if (_norm(j.paymentMethod) == 'cod') {
      cash += j.agreedPrice ?? j.suggestedPrice ?? 0;
    }
  }
  return CourierDayStats(completed: count, cash: cash, estimated: estimated);
}
