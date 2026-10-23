import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../models/job.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_jobs_provider.dart';
import '../../providers/employee_location_provider.dart';
import 'courier_rules.dart';

/// State of the redesigned courier app (FE-COURIER), on the existing
/// [EmployeeJobsProvider] and [EmployeeLocationProvider]: the job list
/// comes from `GET /users/jobs/get`, and every refresh re-syncs location
/// sharing exactly as the old EmployeeJobsScreen did (track the active job,
/// else the availability heartbeat while online, else stop).
class CourierController extends ChangeNotifier {
  CourierController({
    required this.jobsProvider,
    required this.location,
    required this.auth,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    jobsProvider.addListener(notifyListeners);
    location.addListener(notifyListeners);
  }

  final EmployeeJobsProvider jobsProvider;
  final EmployeeLocationProvider location;
  final AuthProvider auth;

  /// Clock for countdowns and "today" (tests).
  final DateTime Function() now;

  Future<void>? _inFlight;
  bool _loaded = false;

  List<Job> get jobs => jobsProvider.jobs;

  /// True once the first fetch finished (with or without an error).
  bool get loaded => _loaded;
  bool get loading => jobsProvider.isLoading;
  String? get error => jobsProvider.error;

  Job? get offer => currentOffer(jobs);

  /// The current job shown: the one picked with [select] while it is still
  /// running, else [currentJob].
  Job? get current {
    final picked = _selectedId;
    if (picked != null) {
      for (final j in jobs) {
        if (j.id == picked && isCurrent(j)) return j;
      }
    }
    return currentJob(jobs);
  }

  /// Every running job (the old screen listed them all).
  List<Job> get running => jobs.where(isCurrent).toList();

  String? _selectedId;

  /// Shows another running job.
  void select(String jobId) {
    _selectedId = jobId;
    notifyListeners();
  }

  int get otherCurrent => otherCurrentCount(jobs);
  bool get activeJobLock => hasActiveJob(jobs);

  /// Re-reads the jobs and re-syncs location sharing. Joins a refresh
  /// already in flight.
  Future<void> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    final token = auth.token;
    if (token == null) return;
    await jobsProvider.fetchAssignedJobs(token);
    _loaded = true;
    notifyListeners();
    await syncTracking();
  }

  /// A fresh refresh after an action: waits for one already in flight
  /// (it may have started before the action), then starts a new one.
  Future<void> reload() async {
    await _inFlight;
    await refresh();
  }

  /// Same rule as the old screen's `_refreshJobs`.
  Future<void> syncTracking() async {
    final token = auth.token;
    if (token == null) return;
    final active = jobs.where(isActive).toList();
    if (active.isNotEmpty) {
      await location.startTracking(active.first.id, token);
    } else if (location.isAvailableOnline) {
      await location.startAvailabilityTracking(token);
    } else {
      await location.stopAvailabilityTracking();
    }
  }

  /// The availability switch (locked while a job is active).
  Future<void> setOnline(bool online) async {
    if (activeJobLock) return;
    await location.setAvailableOnline(online, userToken: auth.token);
  }

  // --- Offer (C-Offer). Each action refetches afterwards, success or not,
  // as the old screen did; errors are rethrown for the page's notice. ---

  Future<void> accept(Job job) async {
    try {
      await jobsProvider.acceptJobOffer(job.id);
    } finally {
      await reload();
    }
  }

  Future<void> decline(Job job) async {
    try {
      await jobsProvider.declineJobOffer(job.id);
    } finally {
      await reload();
    }
  }

  // --- Current job (A-Courier). ---

  /// Confirms the pickup (ADR-0028), then refetches (also after a failure,
  /// so a 409 / 403 converges on the server's state).
  Future<void> pickup(Job job) async {
    try {
      await jobsProvider.pickupJob(job.id);
    } finally {
      await reload();
    }
  }

  /// Completes the job as before (cash_collected for cash orders), with the
  /// collected amount when it differs, then stops the job's location
  /// sharing (as before) and refetches, which restarts the availability
  /// heartbeat when online. A 409 refetches too.
  Future<void> complete(Job job,
      {required bool cashCollected, double? actualAmount}) async {
    try {
      await jobsProvider.completeJobWithAmount(job.id,
          cashCollected: cashCollected, actualCashAmount: actualAmount);
    } on ApiClientException catch (e) {
      if (e.statusCode == 409) await reload();
      rethrow;
    }
    await location.stopTracking();
    await reload();
  }

  /// Sends a cancellation request to the owner (ADR-0027), then refetches.
  Future<void> requestCancellation(Job job, String reason) async {
    final token = auth.token;
    if (token == null) return;
    await jobsProvider.requestCancellation(
        jobId: job.id, reason: reason, employeeToken: token);
    await reload();
  }

  /// Proposes a fare; refetches on success (the page refetches on races).
  Future<void> proposePrice(Job job, double price) async {
    final token = auth.token;
    if (token == null) return;
    await jobsProvider.proposePrice(
        jobId: job.id, proposedPrice: price, employeeToken: token);
    await reload();
  }

  /// Answers the customer's fare ("accept" | "decline"), then refetches.
  Future<void> respondPrice(Job job, String decision) async {
    final token = auth.token;
    if (token == null) return;
    await jobsProvider.respondPrice(
        jobId: job.id, decision: decision, employeeToken: token);
    await reload();
  }

  @override
  void dispose() {
    jobsProvider.removeListener(notifyListeners);
    location.removeListener(notifyListeners);
    super.dispose();
  }
}
