import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/job.dart';

class EmployeeJobsProvider extends ChangeNotifier {
  final ApiClient apiClient;

  List<Job> _jobs = [];
  bool _isLoading = false;
  String? _error;

  List<Job> get jobs => _jobs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  EmployeeJobsProvider(this.apiClient);

  Future<void> fetchAssignedJobs(String employeeToken) async {
    _isLoading = true;
    _error = null;
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

  Future<void> completeJob(String jobId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = apiClient.currentToken ?? '';
      await apiClient.post('/users/jobs/complete', {
        'job_id': jobId,
        'cash_collected': true,
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
          currentLocation: existing.currentLocation,
          paymentMethod: existing.paymentMethod,
          cancellationReason: existing.cancellationReason,
          lockedEscrowAmount: existing.lockedEscrowAmount,
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
          agreedPrice: existing.agreedPrice,
          priceProposalExpiresAt: existing.priceProposalExpiresAt,
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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
