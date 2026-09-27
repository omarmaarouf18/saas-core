import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/job.dart';

class EmployeeJobsProvider extends ChangeNotifier {
  final ApiClient apiClient;

  List<Job> _jobs = [];
  bool _isLoading = false;
  String? _error;
  // S5 stored-error discrimination: the HTTP status behind [_error] (notably
  // 429 lockouts), so screens can pick verbatim-vs-friendly copy and drop the
  // retry affordance on lockouts. Cleared alongside [_error].
  int? _lastErrorStatusCode;

  List<Job> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int? get lastErrorStatusCode => _lastErrorStatusCode;

  EmployeeJobsProvider(this.apiClient);

  Future<void> fetchAssignedJobs(String employeeToken) async {
    _isLoading = true;
    _error = null;
    _lastErrorStatusCode = null;
    notifyListeners();

    try {
      final res = await apiClient.get(
        '/users/jobs/get',
        queryParams: {'requester_id': employeeToken},
      );

      if (res is List) {
        _jobs =
            res.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
      } else if (res is Map && res.containsKey('jobs')) {
        final list = res['jobs'] as List<dynamic>? ?? [];
        _jobs =
            list.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
      } else if (res is Map) {
        // Single job response handled gracefully, but we expect list
        _jobs = [Job.fromJson(res as Map<String, dynamic>)];
      } else {
        _jobs = [];
      }
    } catch (e) {
      debugPrint('Error fetching assigned jobs: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> simulateAction({
    required String email,
    required String action,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiClient.post('/auth/employee/action', {
        'email': email,
        'action': action,
      });
    } catch (e) {
      debugPrint('Error simulating employee action: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> completeJob(String jobId, {bool cashCollected = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = apiClient.currentToken ?? '';
      await apiClient.post('/users/jobs/complete', {
        'job_id': jobId,
        'cash_collected': cashCollected,
        if (token.isNotEmpty) 'requester_id': token,
      });

      final index = _jobs.indexWhere((j) => j.id == jobId);
      if (index != -1) {
        final existing = _jobs[index];
        _jobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: 'completed',
          location: existing.location,
          destination: existing.destination,
          currentLocation: existing.currentLocation,
          paymentMethod: existing.paymentMethod,
          cancellationReason: existing.cancellationReason,
          lockedEscrowAmount: existing.lockedEscrowAmount,
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
          agreedPrice: existing.agreedPrice,
          priceProposalExpiresAt: existing.priceProposalExpiresAt,
          currentOfferedEmployeeId: existing.currentOfferedEmployeeId,
          offerExpiresAt: existing.offerExpiresAt,
          offeredEmployeeIds: existing.offeredEmployeeIds,
          cancellationRequestReason: existing.cancellationRequestReason,
          cancellationRequestedAt: existing.cancellationRequestedAt,
          cancellationRequestStatus: existing.cancellationRequestStatus,
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('Error completing job: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> acceptJobOffer(String jobId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = apiClient.currentToken ?? '';
      final res = await apiClient.post('/users/employee/jobs/$jobId/accept', {
        'job_id': jobId,
        if (token.isNotEmpty) 'requester_id': token,
      });

      if (res is Map && res['job'] != null) {
        final updatedJob = Job.fromJson(res['job'] as Map<String, dynamic>);
        final index = _jobs.indexWhere((j) => j.id == jobId);
        if (index != -1) {
          _jobs[index] = updatedJob;
        } else {
          _jobs.insert(0, updatedJob);
        }
      } else {
        final index = _jobs.indexWhere((j) => j.id == jobId);
        if (index != -1) {
          final existing = _jobs[index];
          _jobs[index] = Job(
            id: existing.id,
            ownerId: existing.ownerId,
            employeeId: existing.employeeId,
            userId: existing.userId,
            serviceId: existing.serviceId,
            status: 'active',
            location: existing.location,
            destination: existing.destination,
            currentLocation: existing.currentLocation,
            paymentMethod: existing.paymentMethod,
            cancellationReason: existing.cancellationReason,
            lockedEscrowAmount: existing.lockedEscrowAmount,
            suggestedPrice: existing.suggestedPrice,
            proposedPrice: existing.proposedPrice,
            proposedBy: existing.proposedBy,
            agreedPrice: existing.agreedPrice,
            priceProposalExpiresAt: existing.priceProposalExpiresAt,
            currentOfferedEmployeeId: null,
            offerExpiresAt: null,
            offeredEmployeeIds: existing.offeredEmployeeIds,
            cancellationRequestReason: existing.cancellationRequestReason,
            cancellationRequestedAt: existing.cancellationRequestedAt,
            cancellationRequestStatus: existing.cancellationRequestStatus,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error accepting job offer: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> declineJobOffer(String jobId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = apiClient.currentToken ?? '';
      await apiClient.post('/users/employee/jobs/$jobId/decline', {
        'job_id': jobId,
        if (token.isNotEmpty) 'requester_id': token,
      });

      _jobs.removeWhere((j) => j.id == jobId);
    } catch (e) {
      debugPrint('Error declining job offer: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Requests cancellation of an assigned job (ADR-0027): the employee asks,
  /// the owner approves. This REPLACES the old direct cancelJob (removed —
  /// employees can no longer cancel through POST /users/jobs/cancel).
  /// On success the local entry is marked with the pending request state
  /// (status UNCHANGED — the trip continues until the owner responds).
  Future<Map<String, dynamic>> requestCancellation({
    required String jobId,
    required String reason,
    required String employeeToken,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      const msg = 'cancel_reason_required';
      _error = msg;
      notifyListeners();
      throw ApiClientException(msg, statusCode: 400);
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/jobs/request-cancellation', {
        'job_id': jobId,
        'reason': trimmedReason,
        'requester_id': employeeToken,
      });

      final index = _jobs.indexWhere((j) => j.id == jobId);
      if (index != -1) {
        final existing = _jobs[index];
        _jobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: existing.status,
          location: existing.location,
          destination: existing.destination,
          currentLocation: existing.currentLocation,
          paymentMethod: existing.paymentMethod,
          cancellationReason: existing.cancellationReason,
          lockedEscrowAmount: existing.lockedEscrowAmount,
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
          agreedPrice: existing.agreedPrice,
          priceProposalExpiresAt: existing.priceProposalExpiresAt,
          currentOfferedEmployeeId: existing.currentOfferedEmployeeId,
          offerExpiresAt: existing.offerExpiresAt,
          offeredEmployeeIds: existing.offeredEmployeeIds,
          cancellationRequestReason: trimmedReason,
          cancellationRequestedAt: DateTime.now(),
          cancellationRequestStatus: 'pending',
          createdAt: existing.createdAt,
          updatedAt: DateTime.now(),
        );
      }

      if (res is Map<String, dynamic>) return res;
      return {
        'message': 'cancellation request submitted for owner approval',
        'cancellation_request_status': 'pending'
      };
    } catch (e) {
      debugPrint('Error requesting cancellation: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Responds to a transport fare proposal (ADR-0006 `RespondPrice`
  /// vocabulary: decision "accept" or "decline"). This mirrors
  /// `MarketplaceProvider.respondPrice`'s request shape (`job_id`, `decision`,
  /// `requester_token` via `ApiClient.respondPrice`) — the same backend
  /// endpoint, not a second one. On success the local entry is replaced with
  /// the server-returned job: accept flips it to `active` (the pending panel
  /// unmounts, the Complete button appears), decline flips it to `cancelled`
  /// with reason `price_disagreement` (terminal — no redispatch — so it drops
  /// out of the assigned list via the screen's existing status filter).
  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String employeeToken,
  }) async {
    _isLoading = true;
    _error = null;
    _lastErrorStatusCode = null;
    notifyListeners();

    try {
      final res = await apiClient.respondPrice(
        jobId: jobId,
        decision: decision,
        requesterToken: employeeToken,
      );

      if (res is Map && res['job'] is Map) {
        final updatedJob =
            Job.fromJson(Map<String, dynamic>.from(res['job'] as Map));
        final index = _jobs.indexWhere((j) => j.id == jobId);
        if (index != -1) {
          _jobs[index] = updatedJob;
        } else {
          _jobs.insert(0, updatedJob);
        }
        return updatedJob;
      }
      // No job envelope (defensive — the handler always returns one):
      // rebuild locally the same way the accept/decline offer fallbacks do.
      final index = _jobs.indexWhere((j) => j.id == jobId);
      if (index != -1) {
        final existing = _jobs[index];
        if (decision == 'accept') {
          _jobs[index] = Job(
            id: existing.id,
            ownerId: existing.ownerId,
            employeeId: existing.employeeId,
            userId: existing.userId,
            serviceId: existing.serviceId,
            status: 'active',
            location: existing.location,
            destination: existing.destination,
            currentLocation: existing.currentLocation,
            paymentMethod: existing.paymentMethod,
            cancellationReason: existing.cancellationReason,
            lockedEscrowAmount: existing.lockedEscrowAmount,
            suggestedPrice: existing.suggestedPrice,
            proposedPrice: existing.proposedPrice,
            proposedBy: existing.proposedBy,
            agreedPrice: existing.proposedPrice ?? existing.suggestedPrice,
            priceProposalExpiresAt: existing.priceProposalExpiresAt,
            currentOfferedEmployeeId: existing.currentOfferedEmployeeId,
            offerExpiresAt: existing.offerExpiresAt,
            offeredEmployeeIds: existing.offeredEmployeeIds,
            cancellationRequestReason: existing.cancellationRequestReason,
            cancellationRequestedAt: existing.cancellationRequestedAt,
            cancellationRequestStatus: existing.cancellationRequestStatus,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          );
          return _jobs[index];
        }
        _jobs.removeWhere((j) => j.id == jobId);
      }
      return null;
    } catch (e) {
      debugPrint('Error responding to price proposal: $e');
      _error = friendlyErrorMessage(e);
      _lastErrorStatusCode = e is ApiClientException ? e.statusCode : null;
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    _lastErrorStatusCode = null;
    notifyListeners();
  }
}
