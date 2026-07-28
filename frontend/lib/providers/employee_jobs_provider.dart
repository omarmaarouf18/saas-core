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

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
