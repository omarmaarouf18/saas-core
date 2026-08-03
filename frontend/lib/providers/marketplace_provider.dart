import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/marketplace_service.dart';
import '../models/job.dart';

class MarketplaceProvider extends ChangeNotifier {
  final ApiClient apiClient;

  List<MarketplaceService> _services = [];
  List<Job> _customerJobs = [];
  bool _isLoading = false;
  String? _error;
  Job? _bookedJob;

  List<MarketplaceService> get services => _services;
  List<Job> get customerJobs => _customerJobs;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Job? get bookedJob => _bookedJob;

  MarketplaceProvider(this.apiClient);

  Future<void> fetchServices({
    bool nearBy = true,
    double lat = 30.0444,
    double lon = 31.2357,
    double radius = 50.0,
    String sortBy = 'price',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.get(
        '/users/services',
        queryParams: {
          'near_by': nearBy.toString(),
          'lat': lat.toString(),
          'lon': lon.toString(),
          'radius': radius.toString(),
          'sort_by': sortBy,
        },
      );

      if (res is Map && res.containsKey('services')) {
        final list = res['services'] as List<dynamic>? ?? [];
        _services = list
            .map((s) => MarketplaceService.fromJson(s as Map<String, dynamic>))
            .toList();
      } else {
        _services = [];
      }
    } catch (e) {
      debugPrint('Error fetching marketplace services: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Job?> bookJob({
    required String serviceId,
    required String userId, // JWT token
    required double latitude,
    required double longitude,
    required String paymentMethod,
  }) async {
    _isLoading = true;
    _error = null;
    _bookedJob = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/jobs/track', {
        'service_id': serviceId,
        'user_id': userId, // Customer JWT token
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'payment_method': paymentMethod,
      });

      if (res is Map && res.containsKey('job')) {
        _bookedJob = Job.fromJson(res['job'] as Map<String, dynamic>);
        return _bookedJob;
      }
      return null;
    } catch (e) {
      debugPrint('Error booking job: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Job?> fetchJobStatus(String jobId, String userToken) async {
    _error = null;
    try {
      final res = await apiClient.get(
        '/users/jobs/get',
        queryParams: {
          'id': jobId,
          'requester_id': userToken,
        },
      );
      if (res is Map) {
        _bookedJob = Job.fromJson(res as Map<String, dynamic>);
        return _bookedJob;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching job status: $e');
      _error = friendlyErrorMessage(e);
      return null;
    }
  }

  Future<Map<String, dynamic>> rateJob({
    required String jobId,
    required String ratedByToken,
    required String ratedUserId,
    required int stars,
    required String comment,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/jobs/rate', {
        'job_id': jobId,
        'rated_by': ratedByToken,
        'rated_user': ratedUserId,
        'stars': stars,
        'comment': comment,
      });
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('Error rating job: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> fetchRatings(String userTokenOrId) async {
    try {
      final res = await apiClient.get('/users/ratings', queryParams: {
        'user_id': userTokenOrId,
      });
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('Error fetching ratings: $e');
      rethrow;
    }
  }

  Future<Job?> proposePrice({
    required String jobId,
    required double proposedPrice,
    required String userToken,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.proposePrice(
        jobId: jobId,
        proposedPrice: proposedPrice,
        requesterToken: userToken,
      );

      if (res is Map && res.containsKey('job')) {
        _bookedJob = Job.fromJson(res['job'] as Map<String, dynamic>);
        return _bookedJob;
      }
      return null;
    } catch (e) {
      debugPrint('Error proposing price: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String userToken,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.respondPrice(
        jobId: jobId,
        decision: decision,
        requesterToken: userToken,
      );

      if (res is Map && res.containsKey('job')) {
        _bookedJob = Job.fromJson(res['job'] as Map<String, dynamic>);
        return _bookedJob;
      }
      return null;
    } catch (e) {
      debugPrint('Error responding to price proposal: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String userToken,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      const msg = 'Reason is required to cancel a job.';
      _error = msg;
      notifyListeners();
      throw ApiClientException(msg, statusCode: 400);
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/jobs/cancel', {
        'job_id': jobId,
        'reason': trimmedReason,
        'requester_id': userToken,
      });

      if (res is Map) {
        if (_bookedJob != null && _bookedJob!.id == jobId) {
          _bookedJob = Job(
            id: _bookedJob!.id,
            ownerId: _bookedJob!.ownerId,
            employeeId: _bookedJob!.employeeId,
            userId: _bookedJob!.userId,
            serviceId: _bookedJob!.serviceId,
            status: 'cancelled',
            location: _bookedJob!.location,
            currentLocation: _bookedJob!.currentLocation,
            paymentMethod: _bookedJob!.paymentMethod,
            cancellationReason: trimmedReason,
            lockedEscrowAmount: _bookedJob!.lockedEscrowAmount,
            suggestedPrice: _bookedJob!.suggestedPrice,
            proposedPrice: _bookedJob!.proposedPrice,
            proposedBy: _bookedJob!.proposedBy,
            agreedPrice: _bookedJob!.agreedPrice,
            priceProposalExpiresAt: _bookedJob!.priceProposalExpiresAt,
            createdAt: _bookedJob!.createdAt,
            updatedAt: DateTime.now(),
          );
        }
        return Map<String, dynamic>.from(res);
      }
      return {};
    } catch (e) {
      debugPrint('Error cancelling job: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Job>> fetchCustomerJobs([String? userToken]) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final queryParams = <String, String>{};
      if (userToken != null && userToken.isNotEmpty) {
        queryParams['requester_token'] = userToken;
      }
      final res = await apiClient.get(
        '/users/jobs/mine',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );

      if (res is List) {
        _customerJobs =
            res.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
      } else {
        _customerJobs = [];
      }
      return _customerJobs;
    } catch (e) {
      debugPrint('Error fetching customer jobs: $e');
      _error = friendlyErrorMessage(e);
      _customerJobs = [];
      return [];
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
