import '../../core/api_client.dart';
import '../../core/job_rules.dart';
import '../../models/job.dart';
import '../customer/order/job_timeline.dart';

/// Rules for the redesigned owner pages (FE-OWNER-1). Every number here is
/// computed from data the app already loads: the owner jobs list
/// (`GET /users/jobs/owner`) and the employees list (`GET /auth/employees`).
/// Nothing is estimated; what the API does not return is not shown.

/// `GetJobsByOwner` returns the newest 100 jobs by `created_at`.
const int kOwnerJobsServerLimit = 100;

String _norm(String? s) => s?.trim().toLowerCase() ?? '';

/// A courier as `GET /auth/employees` returns it: id, username, email,
/// is_active, created_at.
class OwnerEmployee {
  const OwnerEmployee({
    required this.id,
    required this.username,
    required this.email,
    required this.isActive,
    this.createdAt,
    this.kyeStatus,
  });

  final String id;
  final String username;
  final String email;
  final bool isActive;
  final DateTime? createdAt;

  /// The courier's ID-check status. `/auth/employees` does not return it
  /// today, so it is null and not shown; read only if the payload has it.
  final String? kyeStatus;

  String get displayName =>
      username.trim().isNotEmpty ? username.trim() : email.trim();

  factory OwnerEmployee.fromJson(Map<dynamic, dynamic> json) {
    final kye = json['kye_status']?.toString().trim();
    return OwnerEmployee(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isActive: json['is_active'] == true,
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      kyeStatus: kye == null || kye.isEmpty ? null : kye,
    );
  }

  static List<OwnerEmployee> listFrom(Iterable<dynamic> raw) => [
        for (final e in raw)
          if (e is Map) OwnerEmployee.fromJson(e),
      ];
}

/// FIX-COD-RECON's owner-only flag: a COD job completed although the
/// tracked distance was much shorter than the booked one.
class OwnerDistanceReview {
  const OwnerDistanceReview({
    required this.actualKm,
    required this.bookedKm,
    this.flaggedAt,
    this.source,
  });

  final double actualKm;
  final double bookedKm;
  final DateTime? flaggedAt;

  /// `complete_job` or `stuck_job_repair`.
  final String? source;

  static OwnerDistanceReview? fromJson(Object? json) {
    if (json is! Map) return null;
    return OwnerDistanceReview(
      actualKm: (json['actual_km'] as num?)?.toDouble() ?? 0,
      bookedKm: (json['booked_km'] as num?)?.toDouble() ?? 0,
      flaggedAt: json['flagged_at'] is String
          ? DateTime.tryParse(json['flagged_at'] as String)
          : null,
      source: json['source']?.toString(),
    );
  }
}

/// Owner-only job fields the shared [Job] model does not parse.
class OwnerJobExtras {
  const OwnerJobExtras({this.actualCashAmount, this.distanceReview});

  /// Cash the courier recorded at completion (COD).
  final double? actualCashAmount;
  final OwnerDistanceReview? distanceReview;

  static const none = OwnerJobExtras();

  factory OwnerJobExtras.fromJson(Map<String, dynamic>? json) {
    if (json == null) return none;
    return OwnerJobExtras(
      actualCashAmount: (json['actual_cash_amount'] as num?)?.toDouble(),
      distanceReview: OwnerDistanceReview.fromJson(json['distance_review']),
    );
  }
}

enum OwnerOrdersTab { ongoing, done, cancelled }

const Set<String> _cancelledLike = {'cancelled', 'canceled', 'unavailable'};

/// Orders tab of a job: ongoing per core/job_rules.dart; cancelled for
/// cancelled and unavailable (nobody took it); done for everything else
/// (completed, and statuses this client does not know).
OwnerOrdersTab ownerOrdersTabOf(Job job) {
  if (isOngoing(job)) return OwnerOrdersTab.ongoing;
  if (_cancelledLike.contains(_norm(job.status))) {
    return OwnerOrdersTab.cancelled;
  }
  return OwnerOrdersTab.done;
}

bool isCompleted(Job job) => _norm(job.status) == 'completed';

bool isCod(Job job) => _norm(job.paymentMethod) == 'cod';

/// A courier's cancellation request (ADR-0027) waiting for the owner. A
/// leftover "pending" on a finished job is not actionable and is ignored.
bool hasPendingCancellationRequest(Job job) =>
    _norm(job.cancellationRequestStatus) == 'pending' && isOngoing(job);

bool isInReconciliation(Job job) => const {
      'escrow_reconciliation_required',
      'reconciliation_required',
    }.contains(_norm(job.status));

/// Statuses the owner may cancel: the same two as the old dashboard card.
const Set<String> kOwnerCancellableStatuses = {'pending', 'active'};

bool ownerCanCancel(Job job) =>
    kOwnerCancellableStatuses.contains(_norm(job.status));

/// Pending cancellation requests, oldest first (waiting longest on top).
List<Job> pendingCancellationRequests(Iterable<Job> jobs) {
  final list = jobs.where(hasPendingCancellationRequest).toList();
  final far = DateTime.fromMillisecondsSinceEpoch(0);
  list.sort((a, b) => (a.cancellationRequestedAt ?? a.createdAt ?? far)
      .compareTo(b.cancellationRequestedAt ?? b.createdAt ?? far));
  return list;
}

int reconciliationCount(Iterable<Job> jobs) =>
    jobs.where(isInReconciliation).length;

/// Statuses in which an assigned courier is out on the order.
const Set<String> _onJobStatuses = {'assigned', 'active'};

/// The newest order [employeeId] is out on now, or null.
Job? currentJobOf(String employeeId, Iterable<Job> jobs) {
  final mine = jobs.where((j) =>
      j.employeeId == employeeId && _onJobStatuses.contains(_norm(j.status)));
  final sorted = sortNewestFirst(mine);
  return sorted.isEmpty ? null : sorted.first;
}

/// How many of the loaded orders [employeeId] was assigned.
int jobsCountOf(String employeeId, Iterable<Job> jobs) =>
    jobs.where((j) => j.employeeId == employeeId).length;

/// What the owner can say about a courier right now. There is no presence
/// data in either list, so "free" means "active account, not out on an
/// order", not "online".
enum CourierState { onJob, free, frozen }

CourierState courierStateOf(OwnerEmployee e, Iterable<Job> jobs) {
  if (!e.isActive) return CourierState.frozen;
  return currentJobOf(e.id, jobs) != null
      ? CourierState.onJob
      : CourierState.free;
}

enum TeamFilter { all, active, frozen }

bool teamFilterMatches(TeamFilter f, OwnerEmployee e) => switch (f) {
      TeamFilter.all => true,
      TeamFilter.active => e.isActive,
      TeamFilter.frozen => !e.isActive,
    };

bool _sameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Which day "delivered today" counts a completed order on.
enum DeliveredDayBasis {
  /// Every completed order has its delivery time (`status_history`).
  deliveryTime,

  /// No completed order has one (legacy, or none loaded): the day it was
  /// placed.
  orderDay,

  /// Some have, some not: delivery time where known, else the order day.
  mixed,
}

/// The Today tiles. A completed order counts on the device's calendar day
/// it was delivered (its `completed` history entry, job model v2); an older
/// order without a history counts on the day of `created_at` (the only
/// other fixed timestamp; `updated_at` moves with every change).
/// [deliveredBasis] says which rule the loaded orders needed.
class TodaySummary {
  const TodaySummary({
    required this.ongoingNow,
    required this.ordersToday,
    required this.deliveredToday,
    required this.cashToday,
    required this.truncated,
    this.deliveredBasis = DeliveredDayBasis.orderDay,
  });

  /// Ongoing orders among the loaded ones, whatever their day.
  final int ongoingNow;
  final int ordersToday;

  /// Completed orders delivered today (see the class comment).
  final int deliveredToday;

  /// Cash recorded on the COD orders of [deliveredToday]; null when one of
  /// them has no recorded amount (the sum would be wrong, so it is not
  /// shown).
  final double? cashToday;

  final DeliveredDayBasis deliveredBasis;

  /// Every loaded order is from today and the server limit was reached, so
  /// there may be more: the counts are a lower bound.
  final bool truncated;
}

TodaySummary todaySummary(List<Job> jobs,
    OwnerJobExtras Function(String jobId) extrasOf, DateTime now) {
  final today = jobs
      .where((j) => j.createdAt != null && _sameLocalDay(j.createdAt!, now))
      .toList();
  final completed = jobs.where(isCompleted).toList();
  final withTime = completed.where((j) => jobCompletedAt(j) != null).length;
  final delivered = completed.where((j) {
    final day = jobCompletedAt(j) ?? j.createdAt;
    return day != null && _sameLocalDay(day, now);
  }).toList();
  double? cash = 0;
  for (final j in delivered.where(isCod)) {
    final amount = extrasOf(j.id).actualCashAmount;
    if (amount == null) {
      cash = null;
      break;
    }
    cash = cash! + amount;
  }
  return TodaySummary(
    ongoingNow: jobs.where(isOngoing).length,
    ordersToday: today.length,
    deliveredToday: delivered.length,
    cashToday: cash,
    truncated:
        jobs.length >= kOwnerJobsServerLimit && today.length == jobs.length,
    // No completed order loaded: nothing to say, keep the order-day note.
    deliveredBasis: withTime == 0
        ? DeliveredDayBasis.orderDay
        : withTime == completed.length
            ? DeliveredDayBasis.deliveryTime
            : DeliveredDayBasis.mixed,
  );
}

/// Whether [job] was booked on one of the owner's ride (`transport`)
/// services, when the services list is loaded; false otherwise (delivery
/// wording).
bool ownerJobIsRide(List<dynamic> services, Job job) => services.any((s) =>
    s is Map &&
    (s['id'] ?? s['service_id']) == job.serviceId &&
    (s['category'] as String?)?.trim().toLowerCase() == 'transport');

/// Search by order id (with or without the "#QD-" prefix) or courier name.
bool orderMatchesQuery(Job job, String query, String? courierName) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final ref = q.replaceFirst(RegExp(r'^#?qd-'), '').replaceFirst('#', '');
  if (ref.isNotEmpty && job.id.toLowerCase().contains(ref)) return true;
  return courierName != null && courierName.toLowerCase().contains(q);
}

/// 409 on respond-cancellation: the request was already resolved or ran
/// out (ADR-0027).
bool isConflict(Object error) =>
    error is ApiClientException && error.statusCode == 409;

enum ToggleFailure {
  wrongPassword,
  kybNotApproved,
  paidPlanRequired,
  unavailable,
  tooManyTries,
  other,
}

/// Maps a `POST /auth/employee/toggle` failure. Wrong password and an
/// unknown owner both answer 403 "invalid owner credentials"; an owner
/// whose KYB is not approved gets 403 "...KYC approval is pending"; a free
/// tier gets 402 `upgrade_required`; SEC-07b's failed session revocation
/// is 503 (nothing changed).
ToggleFailure toggleFailureOf(Object error) {
  if (error is! ApiClientException) return ToggleFailure.other;
  final msg = error.message.toLowerCase();
  if (error.statusCode == 403 && msg.contains('invalid owner credentials')) {
    return ToggleFailure.wrongPassword;
  }
  if (error.statusCode == 403 && msg.contains('kyc')) {
    return ToggleFailure.kybNotApproved;
  }
  if (error.statusCode == 402 || msg == 'upgrade_required') {
    return ToggleFailure.paidPlanRequired;
  }
  if (error.statusCode == 503 ||
      (error.statusCode == null && error.errorCode == 'service_unavailable')) {
    return ToggleFailure.unavailable;
  }
  if (error.statusCode == 429) return ToggleFailure.tooManyTries;
  return ToggleFailure.other;
}

/// The old employee screen's username rule: 3–30 runes; Latin or Arabic
/// letters, digits, spaces and `_`.
enum UsernameProblem { required, tooShort, tooLong, invalidChars }

UsernameProblem? usernameProblem(String value) {
  final v = value.trim();
  if (v.isEmpty) return UsernameProblem.required;
  if (v.runes.length < 3) return UsernameProblem.tooShort;
  if (v.runes.length > 30) return UsernameProblem.tooLong;
  if (!RegExp(r'^[a-zA-Z0-9_\s؀-ۿ]+$').hasMatch(v)) {
    return UsernameProblem.invalidChars;
  }
  return null;
}

/// The old employee screen's email pattern.
bool isValidEmail(String value) =>
    RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(value.trim());

/// O-Fleet filter (FE-OWNER-2).
enum FleetFilter { all, onJob, free }

/// The order a courier on the map is out on, or null when free.
///
/// The marker's job id comes from the hydration (an active job, or any job
/// updated in the last 15 minutes, including a finished one) or from the
/// live location message. A job we know from the owner jobs list counts
/// only while it is ongoing, so a courier who just delivered shows as free.
/// A job id we do not know (beyond the loaded 100) is trusted.
String? fleetJobIdOf(String? markerJobId, Iterable<Job> jobs) {
  if (markerJobId == null || markerJobId.isEmpty) return null;
  for (final j in jobs) {
    if (j.id == markerJobId) return isOngoing(j) ? j.id : null;
  }
  return markerJobId;
}

bool fleetFilterMatches(FleetFilter f, String? jobId) => switch (f) {
      FleetFilter.all => true,
      FleetFilter.onJob => jobId != null,
      FleetFilter.free => jobId == null,
    };
