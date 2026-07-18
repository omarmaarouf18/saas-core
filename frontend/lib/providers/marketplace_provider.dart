import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../models/marketplace_service.dart';
import '../models/job.dart';

class MarketplaceProvider extends ChangeNotifier {
  final ApiClient apiClient;

  List<MarketplaceService> _services = [];
  bool _isLoading = false;
  String? _error;
  Job? _bookedJob;

  List<MarketplaceService> get services => _services;
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
      _error = e.toString().replaceFirst("ApiClientException: ", "");
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
