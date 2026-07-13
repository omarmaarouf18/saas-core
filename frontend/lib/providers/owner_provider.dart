import 'package:flutter/material.dart';
import '../core/api_client.dart';

class OwnerProvider extends ChangeNotifier {
  final ApiClient apiClient;

  double _walletBalance = 0.0;
  String _subscriptionTier = 'free';
  bool _isLoading = false;
  String? _error;

  double get walletBalance => _walletBalance;
  String get subscriptionTier => _subscriptionTier;
  bool get isLoading => _isLoading;
  String? get error => _error;

  OwnerProvider(this.apiClient);

  Future<void> fetchDashboardData(String tenantId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Fetch Wallet Balance
      final walletRes = await apiClient.get('/users/wallet', queryParams: {'tenant_id': tenantId});
      _walletBalance = (walletRes['balance'] as num?)?.toDouble() ?? 0.0;

      // 2. Fetch Subscription status
      final subRes = await apiClient.get('/users/subscription', queryParams: {'tenant_id': tenantId});
      _subscriptionTier = subRes['tier'] ?? 'free';
    } catch (e) {
      _error = e.toString().replaceFirst("ApiClientException: ", "");
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
