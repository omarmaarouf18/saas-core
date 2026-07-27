import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../models/reconciliation_job.dart';

class ReconciliationProvider extends ChangeNotifier {
  final ApiClient apiClient;

  List<ReconciliationJob> _queue = [];
  bool _isLoading = false;
  String? _error;

  List<ReconciliationJob> get queue => List.unmodifiable(_queue);
  bool get isLoading => _isLoading;
  String? get error => _error;

  ReconciliationProvider(this.apiClient);

  Future<void> fetchQueue() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.get('/users/jobs/reconciliation-queue');
      if (res is List) {
        _queue = res
            .map((e) => ReconciliationJob.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _queue = [];
      }
    } on ApiClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _error = "Access denied: owner authorization required (${e.message})";
      } else if (e.statusCode == 429) {
        _error = e.message;
      } else {
        _error = e.message;
      }
    } catch (e) {
      _error = e.toString().replaceFirst("ApiClientException: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> resolveJob({
    required String jobId,
    required String decision,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiClient.post('/users/jobs/reconciliation-resolve', {
        'job_id': jobId,
        'decision': decision,
      });

      _queue.removeWhere((j) => j.id == jobId);
      return true;
    } on ApiClientException catch (e) {
      if (e.statusCode == 409) {
        _error = "Job already resolved";
      } else if (e.statusCode == 429) {
        _error = e.message;
      } else if (e.statusCode == 401 || e.statusCode == 403) {
        _error = "Access denied: ${e.message}";
      } else {
        _error = e.message;
      }
      return false;
    } catch (e) {
      _error = e.toString().replaceFirst("ApiClientException: ", "");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setError(String? err) {
    _error = err;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
