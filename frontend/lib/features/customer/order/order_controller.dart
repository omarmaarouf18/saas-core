import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../models/job.dart';
import '../../../providers/marketplace_provider.dart';
import 'order_view.dart';

/// State of one order on the order detail page (FE-CUST-2): the last good
/// job, the last refresh error, polling and the customer's actions.
///
/// Polling uses the existing `MarketplaceProvider.fetchJobStatus` every
/// [pollInterval] while the job is not finished (core/job_rules.dart) and
/// stops on finished and on [dispose]. A failed refresh keeps the last
/// good job and sets [error]; the next success clears it.
class OrderController extends ChangeNotifier {
  OrderController({
    required MarketplaceProvider marketplace,
    required String? Function() token,
    required Future<String?> Function(String userId) courierName,
    required String jobId,
    Job? initialJob,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 5),
  })  : _marketplace = marketplace,
        _token = token,
        _courierName = courierName,
        _jobId = jobId,
        _job = initialJob,
        now = now ?? DateTime.now;

  final MarketplaceProvider _marketplace;
  final String? Function() _token;
  final Future<String?> Function(String userId) _courierName;

  /// Clock, injectable for tests (view choice, countdown, timeline).
  final DateTime Function() now;
  final Duration pollInterval;

  String _jobId;
  Job? _job;
  String? _error;
  bool _refreshing = false;
  bool _disposed = false;
  Timer? _poll;
  int _generation = 0;

  String? _courierId;
  String? _courierDisplayName;

  String get jobId => _jobId;

  /// The last good job; null only before the first successful load.
  Job? get job => _job;

  /// The last refresh failed (friendly message); [job] is still shown.
  String? get error => _error;
  bool get refreshing => _refreshing;
  bool get polling => _poll?.isActive ?? false;

  /// Courier name for [courierIdOf], once resolved.
  String? get courierName => _courierDisplayName;

  OrderViewKind? get view => _job == null ? null : orderViewFor(_job!, now());

  /// The courier shown on the page: the assigned employee, or while
  /// searching the one currently looking at the offer (early chat).
  static String? courierIdOf(Job job) {
    final assigned = job.employeeId?.trim() ?? '';
    if (assigned.isNotEmpty) return assigned;
    final offered = job.currentOfferedEmployeeId?.trim() ?? '';
    if (offered.isNotEmpty &&
        job.status.trim().toLowerCase() == 'pending_dispatch') {
      return offered;
    }
    return null;
  }

  /// First load, then polling.
  Future<void> start() async {
    if (_job != null) _resolveCourier();
    await refresh();
    _schedulePolling();
  }

  void _schedulePolling() {
    _poll?.cancel();
    final job = _job;
    if (_disposed || (job != null && !shouldPoll(job))) return;
    _poll = Timer.periodic(pollInterval, (_) {
      if (_refreshing) return; // one request at a time
      refresh();
    });
  }

  /// Fetches the job. Keeps the last good job on failure.
  Future<void> refresh() async {
    final token = _token();
    if (token == null || _disposed) return;
    final gen = ++_generation;
    _refreshing = true;
    _notify();
    final fetched = await _marketplace.fetchJobStatus(_jobId, token);
    if (_disposed || gen != _generation) return; // a newer change owns it
    _refreshing = false;
    if (fetched != null) {
      _apply(fetched);
    } else {
      _error = _marketplace.error ?? '';
      _notify();
    }
  }

  /// Replaces the job with a fresher copy (an action's response).
  void setJob(Job job) {
    _generation++; // an older in-flight refresh must not overwrite this
    _refreshing = false;
    _apply(job);
  }

  void _apply(Job job) {
    _job = job;
    _jobId = job.id.isEmpty ? _jobId : job.id;
    _error = null;
    _resolveCourier();
    if (!shouldPoll(job)) {
      _poll?.cancel();
    } else if (!polling) {
      _schedulePolling();
    }
    _notify();
  }

  void _resolveCourier() {
    final job = _job;
    final id = job == null ? null : courierIdOf(job);
    if (id == _courierId) return;
    _courierId = id;
    _courierDisplayName = null;
    if (id == null) return;
    _courierName(id).then((name) {
      if (_disposed || id != _courierId) return;
      _courierDisplayName = name;
      _notify();
    });
  }

  bool _rated = false;

  /// The customer rated this order in this session (the API has no
  /// "did I rate this job" read; the server answers "already rated" on a
  /// second try, which the rating page treats as success).
  bool get rated => _rated;

  void markRated() {
    _rated = true;
    _notify();
  }

  /// The price proposal countdown reached zero: show the expired view now
  /// and ask the server for the cancelled job.
  void proposalExpired() {
    _notify();
    refresh();
  }

  // --- Actions. Errors propagate to the view, which shows a notice. ---

  /// Cancels with [reason] (existing `cancelJob`), then refetches.
  Future<void> cancel(String reason) async {
    await _marketplace.cancelJob(
      jobId: _jobId,
      reason: reason,
      userToken: _token() ?? '',
    );
    await refresh();
  }

  /// Books the same service, locations, notes and payment method again
  /// (the old "retry booking"); the page then follows the new job.
  Future<Job?> retryBooking() async {
    final old = _job;
    if (old == null) return null;
    final fresh = await _marketplace.bookJob(
      serviceId: old.serviceId,
      userId: _token() ?? '',
      latitude: old.location.latitude,
      longitude: old.location.longitude,
      destinationLatitude: old.destination?.latitude ?? old.location.latitude,
      destinationLongitude:
          old.destination?.longitude ?? old.location.longitude,
      paymentMethod: old.paymentMethod,
      pickupAddressNote: old.location.addressNote,
      destinationAddressNote: old.destination?.addressNote,
    );
    if (fresh != null && !_disposed) setJob(fresh);
    return fresh;
  }

  /// Customer counter-offer (existing `proposePrice`), then refetch.
  Future<void> proposePrice(double price) async {
    final updated = await _marketplace.proposePrice(
      jobId: _jobId,
      proposedPrice: price,
      userToken: _token() ?? '',
    );
    if (updated != null && !_disposed) setJob(updated);
    await refresh();
  }

  /// Accept or decline the courier's proposal (existing `respondPrice`),
  /// then refetch. [decision] is `accept` or `decline`.
  Future<void> respondPrice(String decision) async {
    final updated = await _marketplace.respondPrice(
      jobId: _jobId,
      decision: decision,
      userToken: _token() ?? '',
    );
    if (updated != null && !_disposed) setJob(updated);
    await refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
