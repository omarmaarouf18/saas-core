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
