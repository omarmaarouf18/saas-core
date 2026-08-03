import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/error_messages.dart';
import '../models/job.dart';

class OwnerProvider extends ChangeNotifier {
  final ApiClient apiClient;

  double _walletBalance = 0.0;
  double _escrowBalance = 0.0;
  double _withdrawableBalance = 0.0;
  String _subscriptionTier = 'free';
  List<dynamic> _ledgerEntries = [];
  List<Job> _ownerJobs = [];
  double? _platformFeePercentage;
  bool _isLoading = false;
  String? _error;

  double get walletBalance => _walletBalance;
  double get escrowBalance => _escrowBalance;
  double get withdrawableBalance => _withdrawableBalance;
  String get subscriptionTier => _subscriptionTier;
  List<dynamic> get ledgerEntries => _ledgerEntries;
  List<Job> get ownerJobs => _ownerJobs;
  double? get platformFeePercentage => _platformFeePercentage;
  bool get isLoading => _isLoading;
  String? get error => _error;

  OwnerProvider(this.apiClient);

  Future<void> fetchDashboardData(String tenantId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Fetch Wallet Balance
      final walletRes = await apiClient
          .get('/users/wallet', queryParams: {'tenant_id': tenantId});
      _walletBalance = (walletRes['total_balance'] as num?)?.toDouble() ?? 0.0;
      _escrowBalance = (walletRes['escrow_balance'] as num?)?.toDouble() ?? 0.0;
      _withdrawableBalance =
          (walletRes['withdrawable_balance'] as num?)?.toDouble() ?? 0.0;

      // 2. Fetch Subscription status
      final subRes = await apiClient
          .get('/users/subscription', queryParams: {'tenant_id': tenantId});
      _subscriptionTier = subRes['tier'] ?? 'free';

      // 3. Fetch Ledger entries
      final ledgerRes = await apiClient
          .get('/users/ledger', queryParams: {'tenant_id': tenantId});
      _ledgerEntries = ledgerRes['entries'] as List<dynamic>? ?? [];
    } catch (e) {
      debugPrint('Error fetching owner dashboard data: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deposit(String token, double amount) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await apiClient.post('/users/wallet/deposit', {
        'tenant_id': token,
        'amount': amount,
      });
      // Re-fetch wallet and ledger data on success
      await fetchDashboardData(token);
    } catch (e) {
      debugPrint('Error processing owner deposit: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<dynamic> _auditLogEntries = [];
  List<dynamic> get auditLogEntries => _auditLogEntries;

  // ---------------------------------------------------------------------------
  // API Call: Register Employee
  // Convention: Uses RAW owner ID (ownerId) in 'owner_id' JSON body parameter.
  // Why: /auth/signup validates the owner's existence via direct GetByID lookup.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> registerEmployee({
    required String email,
    required String username,
    required String password,
    required String ownerId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/signup', {
        'email': email,
        'username': username,
        'password': password,
        'role': 'employee',
        'owner_id': ownerId, // RAW ID convention
      });
      return res;
    } catch (e) {
      debugPrint('Error registering employee: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // API Call: Toggle Employee Status (Freeze/Activate)
  // Convention: Uses owner email and owner password (re-auth) in JSON body.
  // Why: /auth/employee/toggle re-verifies the owner password via bcrypt.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> toggleEmployee({
    required String employeeEmail,
    required String ownerEmail,
    required String ownerPassword,
    required bool setActive,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/auth/employee/toggle', {
        'employee_email': employeeEmail,
        'owner_email': ownerEmail,
        'owner_password': ownerPassword, // Password re-auth convention
        'set_active': setActive,
      });
      return res;
    } catch (e) {
      debugPrint('Error toggling employee status: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // API Call: Fetch Tenant Audit Log
  // Convention: Paired query parameters: tenant_id (RAW ID) and requester_id (JWT).
  // Why: auth-service verifies the requester identity (JWT) matches tenant_id.
  // ---------------------------------------------------------------------------
  Future<void> fetchAuditLog({
    required String tenantId,
    required String requesterToken,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.get('/auth/audit-log', queryParams: {
        'tenant_id': tenantId, // RAW ID convention
        'requester_id': requesterToken, // JWT token convention
      });
      _auditLogEntries = res['entries'] as List<dynamic>? ?? [];
    } catch (e) {
      debugPrint('Error fetching audit log: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<dynamic> _services = [];
  List<dynamic> get services => _services;

  // ---------------------------------------------------------------------------
  // API Call: Fetch All Services
  // ---------------------------------------------------------------------------
  Future<void> fetchServices() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.get('/users/services');
      _services = res['services'] as List<dynamic>? ?? [];
    } catch (e) {
      debugPrint('Error fetching services: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // API Call: Create Service (KYC Gated on backend)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> createService({
    required String name,
    required String category,
    required double tenantBasePrice,
    required double tenantPricePerKM,
    required double latitude,
    required double longitude,
    required String ownerId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/services', {
        'owner_id': ownerId,
        'name': name,
        'category': category,
        'tenant_base_price': tenantBasePrice,
        'tenant_price_per_km': tenantPricePerKM,
        'latitude': latitude,
        'longitude': longitude,
      });
      await fetchServices();
      return res;
    } catch (e) {
      debugPrint('Error creating service: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // API Call: Update Subscription
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> updateSubscription({
    required String tenantId,
    required String tier,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.post('/users/subscription', {
        'tenant_id': tenantId,
        'tier': tier,
        'requester_id': tenantId,
      });

      if (res is Map) {
        if (res.containsKey('tier')) {
          _subscriptionTier = res['tier'] ?? 'free';
        } else if (res.containsKey('status')) {
          _subscriptionTier = res['status'] ?? 'pending_payment';
        }
      }
      return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('Error updating subscription: $e');
      _error = friendlyErrorMessage(e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchOwnerJobs(String ownerToken) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await apiClient.get('/users/jobs/owner', queryParams: {
        'owner_token': ownerToken,
      });

      if (res is List) {
        _ownerJobs =
            res.map((j) => Job.fromJson(j as Map<String, dynamic>)).toList();
      } else {
        _ownerJobs = [];
      }
    } catch (e) {
      debugPrint('Error fetching owner jobs: $e');
      _error = friendlyErrorMessage(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String ownerToken,
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
        'requester_id': ownerToken,
      });

      final index = _ownerJobs.indexWhere((j) => j.id == jobId);
      if (index != -1) {
        final existing = _ownerJobs[index];
        _ownerJobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: 'cancelled',
          location: existing.location,
          currentLocation: existing.currentLocation,
          paymentMethod: existing.paymentMethod,
          cancellationReason: trimmedReason,
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
      return Map<String, dynamic>.from(res is Map ? res : {});
    } catch (e) {
      debugPrint('Error cancelling job as owner: $e');
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

  /// Fetches public platform configuration (GET /users/platform/config).
  ///
  /// Caches response in memory after first successful fetch since platform fee parameters change infrequently.
  /// Ignores non-fatal fetch failures to prevent blocking critical UI workflows.
  Future<void> fetchPlatformConfig() async {
    if (_platformFeePercentage != null) return;

    try {
      final res = await apiClient.get('/users/platform/config');
      if (res != null && res is Map) {
        final data = Map<String, dynamic>.from(res);
        if (data.containsKey('platform_fee_percentage')) {
          _platformFeePercentage =
              (data['platform_fee_percentage'] as num?)?.toDouble();
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Non-critical: Error fetching platform config: $e');
    }
  }
}
