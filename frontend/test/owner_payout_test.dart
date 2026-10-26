import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';

class FakeApiClientForPayout extends ApiClient {
  final Map<String, dynamic> mockWalletResponse;
  final List<dynamic> mockPayoutRequestsResponse;

  /// Audit S6/S15: when true, the payout-list endpoint throws, simulating a
  /// transient payout-service outage while wallet/ledger stay healthy.
  bool failPayoutRequests = false;
  Map<String, dynamic>? lastPostedPayoutBody;

  FakeApiClientForPayout({
    this.mockWalletResponse = const {
      'total_balance': 500.0,
      'withdrawable_balance': 200.0,
      'escrow_balance': 100.0,
    },
    this.mockPayoutRequestsResponse = const [],
  });

  @override
  String? get currentToken => 'mock-owner-token';

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/users/wallet') {
      return mockWalletResponse;
    }
    if (path == '/users/subscription') {
      return {'tier': 'paid'};
    }
    if (path == '/users/ledger') {
      return {'entries': []};
    }
    if (path == '/users/platform/config') {
      // PAY-COD-ONLY: these tests exercise the payout dialog, which only
      // opens when digital payments are on.
      return {'digital_payments_enabled': true};
    }
    if (path == '/users/wallet/payout/requests') {
      if (failPayoutRequests) {
        throw ApiClientException('Payout service unavailable', statusCode: 500);
      }
      return mockPayoutRequestsResponse;
    }
    return {};
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/users/wallet/payout/request') {
      lastPostedPayoutBody = body;
      return {
        'id': 'payout-test-101',
        'tenant_id': 'owner-test-1',
        'amount': (body['amount'] as num).toDouble(),
        'status': 'requested',
        'payout_method': body['payout_method'],
        'account_details': body['account_details'],
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
    }
    return {};
  }
}

class TestAuthProvider extends AuthProvider {
  TestAuthProvider(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-test-1',
        email: 'owner@example.com',
        username: 'test_owner',
        role: 'owner',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-owner-token';
}

void main() {
  // UX-05: no fake trend data — the mock balance trend chip must stay gone.

  test('Audit S6: payout-list failure keeps the last-good cached list',
      () async {
    final fakeApi = FakeApiClientForPayout(
      mockPayoutRequestsResponse: [
        {
          'id': 'payout-1',
          'tenant_id': 'owner-test-1',
          'amount': 120.0,
          'status': 'requested',
          'payout_method': 'instapay',
          'account_details': 'wallet-123',
          'created_at': '2026-09-20T10:00:00Z',
          'updated_at': '2026-09-20T10:00:00Z',
        },
      ],
    );
    final ownerProvider = OwnerProvider(fakeApi);

    await ownerProvider.fetchPayoutRequests();
    expect(ownerProvider.payoutRequests, hasLength(1));
    expect(ownerProvider.error, isNull);

    // Transient outage: the cached entry survives, the banner owns the
    // signal — no wiped list, no contradictory empty state.
    fakeApi.failPayoutRequests = true;
    await ownerProvider.fetchPayoutRequests();
    expect(ownerProvider.payoutRequests, hasLength(1));
    expect(ownerProvider.payoutRequests.first.id, 'payout-1');
    expect(ownerProvider.error, isNotNull);
  });
}

class MockOwnerProviderWithCustomError extends OwnerProvider {
  final String? testError;
  int refreshCalls = 0;

  MockOwnerProviderWithCustomError(super.apiClient, {this.testError});

  @override
  String? get error => testError;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchDashboardData(String tenantId) async {
    refreshCalls++;
  }

  @override
  Future<List<PayoutRequest>> fetchPayoutRequests() async => [];
}

/// Audit S11: pins the shared in-flight flag so the mid-refresh window is
/// deterministic without depending on async fetch timing.
class LoadingPinnedOwnerProvider extends OwnerProvider {
  LoadingPinnedOwnerProvider(super.apiClient);

  @override
  bool get isLoading => true;
}
