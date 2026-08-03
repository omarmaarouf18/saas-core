import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/kyb_kye_review_screen.dart';
import 'package:frontend/widgets/status_badge.dart';
import 'package:frontend/widgets/document_viewer_dialog.dart';

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
  bool shouldFailPending = false;
  bool shouldFailDocument = false;
  bool shouldDelayDocument = false;
  bool fetchPendingCalled = false;
  String? lastInternalToken;
  String? lastReviewerToken;
  String? lastFetchedDocumentUrl;

  MockAuthProviderForReviewTest(super.apiClient, {this.mockUser});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => 'test-token-123';

  @override
  List<dynamic> get pendingSubmissions => mockPendingSubmissions;

  @override
  bool get isLoadingPending => mockIsLoadingPending;

  @override
  String? get pendingError => mockPendingError;

  @override
  Future<void> fetchUserProfile() async {}

  @override
  Future<List<dynamic>> fetchPendingSubmissions({
    String? internalToken,
    String? reviewerToken,
  }) async {
    fetchPendingCalled = true;
    lastInternalToken = internalToken;
    lastReviewerToken = reviewerToken;
    mockIsLoadingPending = false;
    if (shouldFailPending) {
      mockPendingError = 'Failed to load reviewer queue';
      mockPendingSubmissions = [];
      notifyListeners();
      return [];
    }
    notifyListeners();
    return mockPendingSubmissions;
  }

  @override
  Future<Uint8List> fetchDocumentBytes(
    String documentUrl, {
    String? internalToken,
    String? reviewerToken,
  }) async {
    lastFetchedDocumentUrl = documentUrl;
    if (shouldDelayDocument) {
      await Future.delayed(const Duration(seconds: 5));
    }
    if (shouldFailDocument) {
      throw ApiClientException('Failed to load document preview');
    }
    // Return dummy 1x1 PNG transparent image bytes
    return Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82
    ]);
  }
}

class MockOwnerProviderForReviewTest extends OwnerProvider {
  MockOwnerProviderForReviewTest(super.apiClient);

  @override
  Future<void> fetchDashboardData(String ownerToken) async {}

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {}
}

class MockNotificationsProviderForReviewTest extends NotificationsProvider {
  MockNotificationsProviderForReviewTest(super.apiClient);

  @override
  int get unreadCount => 0;
}

class MockMarketplaceProviderForReviewTest extends MarketplaceProvider {
  MockMarketplaceProviderForReviewTest(super.apiClient);
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
    expect(
        authProvider.pendingSubmissions[0]['username'], equals('Acme Owner'));
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

  Widget createHomeScreenWidget({
    required MockAuthProviderForReviewTest authProvider,
  }) {
    final apiClient = ApiClient();
    final ownerProvider = MockOwnerProviderForReviewTest(apiClient);
    final notificationsProvider =
        MockNotificationsProviderForReviewTest(apiClient);
    final marketplaceProvider = MockMarketplaceProviderForReviewTest(apiClient);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
        ChangeNotifierProvider<NotificationsProvider>.value(
            value: notificationsProvider),
        ChangeNotifierProvider<MarketplaceProvider>.value(
            value: marketplaceProvider),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
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

    await tester
        .pumpWidget(createKybKyeReviewScreenWidget(authProvider: mockAuth));
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

    await tester
        .pumpWidget(createKybKyeReviewScreenWidget(authProvider: mockAuth));
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

    await tester
        .pumpWidget(createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_list_view')), findsOneWidget);
    expect(find.byKey(const Key('submission_item_owner-101')), findsOneWidget);
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
    mockAuth.shouldFailPending = true;

    await tester
        .pumpWidget(createKybKyeReviewScreenWidget(authProvider: mockAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyb_kye_error_banner')), findsOneWidget);
    expect(find.text('Failed to load reviewer queue'), findsOneWidget);
  });

  testWidgets(
      '5. Navigation Entry Point: Visible for reviewer/admin roles and hidden for other roles',
      (WidgetTester tester) async {
    final apiClient = ApiClient();

    // Case A: Reviewer role -> KybKyeReviewScreen rendered directly on HomeScreen
    final reviewerUser = UserProfile(
      id: 'rev-1',
      email: 'reviewer@admin.com',
      username: 'ReviewerUser',
      role: 'reviewer',
    );
    final reviewerAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: reviewerUser);

    await tester.pumpWidget(createHomeScreenWidget(authProvider: reviewerAuth));
    await tester.pumpAndSettle();

    expect(find.byType(KybKyeReviewScreen), findsOneWidget);
    expect(find.text('Pending KYB/KYE Submissions'), findsOneWidget);

    // Case B: Admin role -> KybKyeReviewScreen rendered directly on HomeScreen
    final adminUser = UserProfile(
      id: 'admin-1',
      email: 'admin@system.com',
      username: 'AdminUser',
      role: 'admin',
    );
    final adminAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: adminUser);

    await tester.pumpWidget(createHomeScreenWidget(authProvider: adminAuth));
    await tester.pumpAndSettle();

    expect(find.byType(KybKyeReviewScreen), findsOneWidget);

    // Case C: Owner role -> reviewer_queue_button absent
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'OwnerUser',
      role: 'owner',
    );
    final ownerAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: ownerUser);

    await tester.pumpWidget(createHomeScreenWidget(authProvider: ownerAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reviewer_queue_button')), findsNothing);

    // Case D: Customer (user) role -> reviewer_queue_button absent
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'CustomerUser',
      role: 'user',
    );
    final customerAuth =
        MockAuthProviderForReviewTest(apiClient, mockUser: customerUser);

    await tester.pumpWidget(createHomeScreenWidget(authProvider: customerAuth));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reviewer_queue_button')), findsNothing);
  });

  testWidgets(
      '6. Document Fetch Success: Renders image and PDF previews in DocumentViewerDialog',
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

    final submission = {
      'user_id': 'owner-101',
      'username': 'Acme Owner',
      'email': 'owner@acme.com',
      'role': 'owner',
      'kyc_status': 'pending_super_admin_approval',
      'id_front_url': 'https://storage/id_front_101.png',
      'id_back_url': 'https://storage/id_back_101.png',
      'selfie_url': 'https://storage/selfie_101.png',
      'business_proof_url': 'https://storage/proof_101.pdf',
    };

    // Case A: Image preview (Front ID)
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: mockAuth,
        child: MaterialApp(
          home: Scaffold(
            body: DocumentViewerDialog(
              key: const Key('doc_dialog_case_a'),
              submission: submission,
              initialDocType: 'id_front',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document_viewer_dialog')), findsOneWidget);
    expect(find.byKey(const Key('document_image_preview')), findsOneWidget);
    expect(mockAuth.lastFetchedDocumentUrl,
        equals('https://storage/id_front_101.png'));

    // Case B: PDF preview (Business Proof)
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: mockAuth,
        child: MaterialApp(
          home: Scaffold(
            body: DocumentViewerDialog(
              key: const Key('doc_dialog_case_b'),
              submission: submission,
              initialDocType: 'business_proof',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document_pdf_preview')), findsOneWidget);
    expect(find.text('PDF Document Preview'), findsOneWidget);
    expect(mockAuth.lastFetchedDocumentUrl,
        equals('https://storage/proof_101.pdf'));
  });

  testWidgets(
      '7. Document Fetch Failure: Renders error banner in DocumentViewerDialog',
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
    mockAuth.shouldFailDocument = true;

    final submission = {
      'user_id': 'owner-101',
      'username': 'Acme Owner',
      'role': 'owner',
      'id_front_url': 'https://storage/id_front_101.png',
    };

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: mockAuth,
        child: MaterialApp(
          home: Scaffold(
            body: DocumentViewerDialog(
              submission: submission,
              initialDocType: 'id_front',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document_error_banner')), findsOneWidget);
    expect(find.text('Failed to load document preview'), findsOneWidget);
  });

  testWidgets(
      '8. Document Loading State: Renders loading indicator in DocumentViewerDialog',
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
    mockAuth.shouldDelayDocument = true;

    final submission = {
      'user_id': 'owner-101',
      'username': 'Acme Owner',
      'role': 'owner',
      'id_front_url': 'https://storage/id_front_101.png',
    };

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: mockAuth,
        child: MaterialApp(
          home: Scaffold(
            body: DocumentViewerDialog(
              submission: submission,
              initialDocType: 'id_front',
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // Trigger build without settling async delay

    expect(find.byKey(const Key('document_loading_indicator')), findsOneWidget);
    expect(find.text('Loading document preview...'), findsOneWidget);

    // Advance timer to complete pending delay and avoid dangling timer
    await tester.pump(const Duration(seconds: 6));
  });
}
