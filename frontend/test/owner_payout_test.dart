import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/wallet_screen.dart';

class FakeApiClientForPayout extends ApiClient {
  final Map<String, dynamic> mockWalletResponse;
  final List<dynamic> mockPayoutRequestsResponse;
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
      return {'platform_fee_percentage': 0.0};
    }
    if (path == '/users/wallet/payout/requests') {
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

Widget createWalletTestWidget({
  required ApiClient apiClient,
  required OwnerProvider ownerProvider,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => TestAuthProvider(apiClient),
      ),
      ChangeNotifierProvider<OwnerProvider>.value(
        value: ownerProvider,
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WalletScreen(),
    ),
  );
}

void main() {
  testWidgets(
      'Payout request form validation - amount exceeds balance and empty details',
      (WidgetTester tester) async {
    final fakeApi = FakeApiClientForPayout();
    final ownerProvider = OwnerProvider(fakeApi);
    await ownerProvider.fetchDashboardData('mock-owner-token');

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    // Tap Request Payout button
    final requestBtn = find.byKey(const Key('request_payout_button'));
    expect(requestBtn, findsOneWidget);
    // The AppBar added in the visual-fix pass nudges this button just below
    // the 800px test viewport; bring it into view before tapping.
    await tester.ensureVisible(requestBtn);
    await tester.pumpAndSettle();
    await tester.tap(requestBtn);
    await tester.pumpAndSettle();

    // Verify dialog title inside Dialog
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('Request Payout')),
        findsOneWidget);

    // Enter amount greater than withdrawable balance (200.0) -> e.g. 500.0
    final amountField = find.descendant(
      of: find.byKey(const Key('payout_amount_field')),
      matching: find.byType(TextField),
    );
    await tester.enterText(amountField, '500.0');

    // Tap Continue
    final submitBtn = find.byKey(const Key('payout_submit_button'));
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // Validation error for amount exceeding balance
    expect(find.text('Amount exceeds current withdrawable balance.'),
        findsOneWidget);

    // Enter valid amount 50.0, but leave details empty
    await tester.enterText(amountField, '50.0');
    await tester.tap(submitBtn);
    await tester.pumpAndSettle();

    // Validation error for missing account details
    expect(find.text('Account details are required.'), findsOneWidget);
  });

  testWidgets(
      'Payout request flow - confirmation step and successful submission',
      (WidgetTester tester) async {
    final fakeApi = FakeApiClientForPayout();
    final ownerProvider = OwnerProvider(fakeApi);
    await ownerProvider.fetchDashboardData('mock-owner-token');

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    // Open Request Payout dialog
    await tester.ensureVisible(find.byKey(const Key('request_payout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('request_payout_button')));
    await tester.pumpAndSettle();

    // Fill valid form details
    final amountField = find.descendant(
      of: find.byKey(const Key('payout_amount_field')),
      matching: find.byType(TextField),
    );
    final detailsField = find.descendant(
      of: find.byKey(const Key('payout_account_details_field')),
      matching: find.byType(TextField),
    );

    await tester.enterText(amountField, '75.0');
    await tester.enterText(detailsField, 'EG1234567890');

    // Tap Continue -> triggers confirmation step
    await tester.tap(find.byKey(const Key('payout_submit_button')));
    await tester.pumpAndSettle();

    // Confirmation step assertions
    expect(find.text('Confirm Payout Request'), findsOneWidget);
    expect(find.textContaining('75.00 credits'), findsOneWidget);
    expect(find.byKey(const Key('payout_confirm_button')), findsOneWidget);

    // Tap Confirm Payout
    await tester.tap(find.byKey(const Key('payout_confirm_button')));
    await tester.pumpAndSettle();

    // Verify backend call payload
    expect(fakeApi.lastPostedPayoutBody, isNotNull);
    expect(fakeApi.lastPostedPayoutBody!['amount'], 75.0);
    expect(fakeApi.lastPostedPayoutBody!['payout_method'], 'bank_transfer');
    expect(fakeApi.lastPostedPayoutBody!['account_details'], 'EG1234567890');

    // SnackBar message shown
    expect(find.byKey(const Key('payout_success_snackbar')), findsOneWidget);
    expect(find.text('Payout request submitted successfully.'), findsOneWidget);
  });

  testWidgets('Payout history rendering across all 4 PayoutStatus values',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final mockRequests = [
      {
        'id': 'p1',
        'tenant_id': 'owner-test-1',
        'amount': 100.0,
        'status': 'requested',
        'payout_method': 'bank_transfer',
        'account_details': 'EG1111111111',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      {
        'id': 'p2',
        'tenant_id': 'owner-test-1',
        'amount': 200.0,
        'status': 'approved',
        'payout_method': 'instapay',
        'account_details': '01012345678',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      {
        'id': 'p3',
        'tenant_id': 'owner-test-1',
        'amount': 300.0,
        'status': 'rejected',
        'payout_method': 'bank_transfer',
        'account_details': 'EG2222222222',
        'rejection_reason': 'Invalid IBAN checksum',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      {
        'id': 'p4',
        'tenant_id': 'owner-test-1',
        'amount': 400.0,
        'status': 'paid',
        'payout_method': 'instapay',
        'account_details': '01099998888',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
    ];

    final fakeApi = FakeApiClientForPayout(
      mockPayoutRequestsResponse: mockRequests,
    );
    final ownerProvider = OwnerProvider(fakeApi);

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    // Section header
    expect(find.byKey(const Key('payout_history_header')), findsOneWidget);
    expect(find.text('Payout Requests History'), findsOneWidget);

    // Tiles rendered
    expect(find.byKey(const Key('payout_tile_p1')), findsOneWidget);
    expect(find.byKey(const Key('payout_tile_p2')), findsOneWidget);
    expect(find.byKey(const Key('payout_tile_p3')), findsOneWidget);
    expect(find.byKey(const Key('payout_tile_p4')), findsOneWidget);

    // Status badges
    expect(find.byKey(const Key('payout_status_badge_p1')), findsOneWidget);
    expect(find.byKey(const Key('payout_status_badge_p2')), findsOneWidget);
    expect(find.byKey(const Key('payout_status_badge_p3')), findsOneWidget);
    expect(find.byKey(const Key('payout_status_badge_p4')), findsOneWidget);

    // Status labels
    expect(find.text('REQUESTED'), findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);
    expect(find.text('REJECTED'), findsOneWidget);
    expect(find.text('PAID'), findsOneWidget);

    // Rejection reason text for p3
    expect(find.byKey(const Key('payout_rejection_reason_p3')), findsOneWidget);
    expect(find.textContaining('Invalid IBAN checksum'), findsOneWidget);
  });

  testWidgets('Payout UI Arabic Egyptian market localization test',
      (WidgetTester tester) async {
    final mockRequests = [
      {
        'id': 'p-ar-1',
        'tenant_id': 'owner-test-1',
        'amount': 150.0,
        'status': 'requested',
        'payout_method': 'instapay',
        'account_details': '01000000000',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    ];

    final fakeApi = FakeApiClientForPayout(
      mockPayoutRequestsResponse: mockRequests,
    );
    final ownerProvider = OwnerProvider(fakeApi);

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();

    // Arabic Section Header and Status Badge
    expect(find.text('سجل طلبات السحب'), findsOneWidget);
    expect(find.text('طلب سحب الأرباح'), findsOneWidget);
    expect(find.text('تم الطلب'), findsOneWidget);
  });

  testWidgets('WalletScreen error banner renders when ownerProvider.error is set',
      (WidgetTester tester) async {
    final fakeApi = FakeApiClientForPayout();
    final ownerProvider = MockOwnerProviderWithCustomError(
      fakeApi,
      testError: 'Failed to load wallet ledger',
    );

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet_screen_error')), findsOneWidget);
    expect(find.text('Failed to load wallet ledger'), findsOneWidget);
  });

  testWidgets('WalletScreen error banner is absent on successful load (error is null)',
      (WidgetTester tester) async {
    final fakeApi = FakeApiClientForPayout();
    final ownerProvider = OwnerProvider(fakeApi);
    await ownerProvider.fetchDashboardData('mock-owner-token');

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet_screen_error')), findsNothing);
  });

  testWidgets('Tapping retry on WalletScreen error banner re-triggers fetch',
      (WidgetTester tester) async {
    final fakeApi = FakeApiClientForPayout();
    final ownerProvider = MockOwnerProviderWithCustomError(
      fakeApi,
      testError: 'Network timeout',
    );

    await tester.pumpWidget(createWalletTestWidget(
      apiClient: fakeApi,
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    final retryButton = find.descendant(
      of: find.byKey(const Key('wallet_screen_error')),
      matching: find.byType(TextButton),
    );
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(ownerProvider.refreshCalls, greaterThanOrEqualTo(1));
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
  Future<void> fetchPlatformConfig() async {}

  @override
  Future<List<PayoutRequest>> fetchPayoutRequests() async => [];
}
