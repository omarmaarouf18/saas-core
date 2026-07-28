import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
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
    } catch (e) {
      debugPrint('Error fetching reconciliation queue: $e');
      _error = friendlyErrorMessage(e);
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
    } catch (e) {
      debugPrint('Error resolving job: $e');
      _error = friendlyErrorMessage(e);
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
