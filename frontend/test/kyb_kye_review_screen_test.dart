import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/kyb_kye_review_screen.dart';
import 'package:frontend/widgets/status_badge.dart';

class MockApiClientForReviewTest extends ApiClient {
  bool shouldFail = false;
  Map<String, String>? lastQueryParams;
  List<dynamic> mockResponse = [
    {
      'user_id': 'owner-101',
      'username': 'Acme Owner',
      'email': 'owner@acme.com',
      'role': 'owner',
      'kyc_status': 'pending_super_admin_approval',
      'id_front_url': 'https://storage/id_front_101.png',
      'id_back_url': 'https://storage/id_back_101.png',
      'selfie_url': 'https://storage/selfie_101.png',
      'business_proof_url': 'https://storage/proof_101.pdf',
    },
    {
      'user_id': 'emp-102',
      'username': 'Sarah Employee',
      'email': 'sarah@acme.com',
      'role': 'employee',
      'kye_status': 'pending_super_admin_approval',
      'id_front_url': 'https://storage/id_front_102.png',
      'id_back_url': 'https://storage/id_back_102.png',
      'selfie_url': 'https://storage/selfie_102.png',
      'document_errors': ['Failed to load id_back: connection reset'],
    },
  ];

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams, bool isRetry = false}) async {
    if (endpoint == '/auth/kyb-kye/pending') {
      lastQueryParams = queryParams;
      if (shouldFail) {
        throw ApiClientException('Failed to load pending submissions queue',
            statusCode: 500);
      }
      return mockResponse;
    }
    return {};
  }
}

class MockAuthProviderForReviewTest extends AuthProvider {
  final UserProfile? mockUser;
  List<dynamic> mockPendingSubmissions = [];
  bool mockIsLoadingPending = false;
  String? mockPendingError;
  bool fetchPendingCalled = false;
  String? lastInternalToken;
  String? lastReviewerToken;

  MockAuthProviderForReviewTest(super.apiClient, {this.mockUser});

  @override
  UserProfile? get user => mockUser;

  @override
  List<dynamic> get pendingSubmissions => mockPendingSubmissions;

  @override
  bool get isLoadingPending => mockIsLoadingPending;

  @override
  String? get pendingError => mockPendingError;

  @override
  Future<List<dynamic>> fetchPendingSubmissions({
    String? internalToken,
    String? reviewerToken,
  }) async {
    fetchPendingCalled = true;
    lastInternalToken = internalToken;
    lastReviewerToken = reviewerToken;
    return mockPendingSubmissions;
  }
}

void main() {
  test(
      'AuthProvider.fetchPendingSubmissions sends query parameters and returns array',
      () async {
    final apiClient = MockApiClientForReviewTest();
    final authProvider = AuthProvider(apiClient);

    expect(authProvider.pendingSubmissions, isEmpty);

    final res = await authProvider.fetchPendingSubmissions(
      internalToken: 'internal-secret-123',
      reviewerToken: 'reviewer-token-456',
    );

    expect(res.length, equals(2));
    expect(authProvider.pendingSubmissions.length, equals(2));
    expect(authProvider.pendingSubmissions[0]['username'], equals('Acme Owner'));
    expect(authProvider.pendingSubmissions[1]['username'],
        equals('Sarah Employee'));
    expect(apiClient.lastQueryParams, isNotNull);
    expect(apiClient.lastQueryParams!['internal_token'],
        equals('internal-secret-123'));
    expect(apiClient.lastQueryParams!['reviewer_token'],
        equals('reviewer-token-456'));
  });

  test(
      'AuthProvider.fetchPendingSubmissions sets error message on network failure',
      () async {
    final apiClient = MockApiClientForReviewTest();
    apiClient.shouldFail = true;
    final authProvider = AuthProvider(apiClient);

    final res = await authProvider.fetchPendingSubmissions();

    expect(res, isEmpty);
    expect(authProvider.pendingSubmissions, isEmpty);
    expect(authProvider.pendingError, isNotNull);
  });

  Widget createKybKyeReviewScreenWidget({
    required MockAuthProviderForReviewTest authProvider,
    String? internalToken,
    String? reviewerToken,
  }) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: MaterialApp(
        home: KybKyeReviewScreen(
          internalToken: internalToken,
          reviewerToken: reviewerToken,
        ),
      ),
    );
  }

  testWidgets(
      '1. Role-gating check: Non-reviewer accounts see Access Denied state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final nonReviewerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'RegularOwner',
      role: 'owner',
    );
    final mockAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: nonReviewerUser);

    await tester.pumpWidget(
        createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_unauthorized_state')), findsOneWidget);
    expect(find.text('Access Denied'), findsOneWidget);
    expect(
      find.text(
          'This reviewer queue is restricted to authorized reviewer accounts only.'),
      findsOneWidget,
    );
    expect(mockAuth.fetchPendingCalled, isFalse);
  });

  testWidgets(
      '2. Role-gating pass & Empty State: Reviewer account with zero pending submissions',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final reviewerUser = UserProfile(
      id: 'rev-1',
      email: 'reviewer@admin.com',
      username: 'ReviewerAdmin',
      role: 'reviewer',
    );
    final mockAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: reviewerUser);
    mockAuth.mockPendingSubmissions = [];
    mockAuth.mockIsLoadingPending = false;

    await tester.pumpWidget(
        createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_empty_state')), findsOneWidget);
    expect(find.text('No Pending Submissions'), findsOneWidget);
    expect(
      find.text('All KYB/KYE verification requests have been processed.'),
      findsOneWidget,
    );
    expect(mockAuth.fetchPendingCalled, isTrue);
  });

  testWidgets(
      '3. Submissions List Rendering: Renders cards for owner and employee submissions',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final reviewerUser = UserProfile(
      id: 'rev-1',
      email: 'reviewer@admin.com',
      username: 'ReviewerAdmin',
      role: 'reviewer',
    );
    final mockAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: reviewerUser);
    mockAuth.mockPendingSubmissions = [
      {
        'user_id': 'owner-101',
        'username': 'Acme Owner',
        'email': 'owner@acme.com',
        'role': 'owner',
        'kyc_status': 'pending_super_admin_approval',
        'id_front_url': 'https://storage/id_front_101.png',
        'id_back_url': 'https://storage/id_back_101.png',
        'selfie_url': 'https://storage/selfie_101.png',
        'business_proof_url': 'https://storage/proof_101.pdf',
      },
      {
        'user_id': 'emp-102',
        'username': 'Sarah Employee',
        'email': 'sarah@acme.com',
        'role': 'employee',
        'kye_status': 'pending_super_admin_approval',
        'id_front_url': 'https://storage/id_front_102.png',
        'id_back_url': 'https://storage/id_back_102.png',
        'selfie_url': 'https://storage/selfie_102.png',
        'document_errors': ['Failed to load id_back: connection reset'],
      },
    ];
    mockAuth.mockIsLoadingPending = false;

    await tester.pumpWidget(
        createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_list_view')), findsOneWidget);
    expect(
        find.byKey(const Key('submission_item_owner-101')), findsOneWidget);
    expect(find.byKey(const Key('submission_item_emp-102')), findsOneWidget);

    expect(find.text('Acme Owner'), findsOneWidget);
    expect(find.text('owner@acme.com'), findsOneWidget);
    expect(find.text('KYB (Owner)'), findsOneWidget);

    expect(find.text('Sarah Employee'), findsOneWidget);
    expect(find.text('sarah@acme.com'), findsOneWidget);
    expect(find.text('KYE (Employee)'), findsOneWidget);

    expect(find.byType(StatusBadge), findsNWidgets(2));
    expect(find.text('• Failed to load id_back: connection reset'),
        findsOneWidget);
  });

  testWidgets(
      '4. Error Banner: Renders error banner when fetchPendingSubmissions fails',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final reviewerUser = UserProfile(
      id: 'rev-1',
      email: 'reviewer@admin.com',
      username: 'ReviewerAdmin',
      role: 'reviewer',
    );
    final mockAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: reviewerUser);
    mockAuth.mockPendingSubmissions = [];
    mockAuth.mockIsLoadingPending = false;
    mockAuth.mockPendingError = 'Failed to load reviewer queue';

    await tester.pumpWidget(
        createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_error_banner')), findsOneWidget);
    expect(find.text('Failed to load reviewer queue'), findsOneWidget);
  });
}
