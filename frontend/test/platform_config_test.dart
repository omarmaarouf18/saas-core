import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/wallet_screen.dart';
import 'package:provider/provider.dart';

class MockApiClientForConfigTest extends ApiClient {
  bool shouldFail = false;
  Map<String, dynamic> mockConfigResponse = {
    'id': 'config-global-1',
    'platform_fee_percentage': 5.0,
    'platform_wallet_id': 'wallet-internal-secret-999',
  };

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (endpoint == '/users/platform/config') {
      if (shouldFail) {
        throw ApiClientException('Internal Server Error', statusCode: 500);
      }
      return mockConfigResponse;
    }
    if (endpoint == '/users/wallet') {
      return {
        'total_balance': 100.0,
        'escrow_balance': 20.0,
        'withdrawable_balance': 80.0,
      };
    }
    if (endpoint == '/users/subscription') {
      return {'tier': 'pro'};
    }
    if (endpoint == '/users/ledger') {
      return {'count': 0, 'entries': []};
    }
    return {};
  }
}

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;
}

void main() {
  late MockApiClientForConfigTest apiClient;
  late MockAuthProviderForTest authProvider;
  late OwnerProvider ownerProvider;

  setUp(() {
    apiClient = MockApiClientForConfigTest();
    authProvider = MockAuthProviderForTest(
      apiClient,
      mockUser: UserProfile(
        id: 'owner-1',
        email: 'owner@example.com',
        username: 'OwnerUser',
        role: 'owner',
      ),
    );
    ownerProvider = OwnerProvider(apiClient);
  });

  Widget buildWalletScreenWidget() {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
        ],
        child: const WalletScreen(),
      ),
    );
  }

  test(
      '(a) Fee percentage renders correctly given a mock response (GET /users/platform/config)',
      () async {
    await ownerProvider.fetchPlatformConfig();
    expect(ownerProvider.platformFeePercentage, equals(5.0));
  });

  testWidgets(
      '(a) & (b) Fee percentage renders in WalletScreen and platform_wallet_id is NEVER rendered',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    apiClient.mockConfigResponse = {
      'id': 'config-global-1',
      'platform_fee_percentage': 7.5,
      'platform_wallet_id': 'SECRET_INTERNAL_WALLET_ID_9999',
    };

    await tester.pumpWidget(buildWalletScreenWidget());
    await tester.pumpAndSettle();

    // (a) Verify fee percentage renders
    expect(
        find.byKey(const Key('platform_fee_percentage_text')), findsOneWidget);
    expect(find.text('Platform fee: 7.5%'), findsOneWidget);

    // (b) Security assertion: platform_wallet_id string must NEVER be rendered in the UI
    expect(find.textContaining('SECRET_INTERNAL_WALLET_ID_9999'), findsNothing);
    expect(find.textContaining('platform_wallet_id'), findsNothing);
  });

  testWidgets(
      '(c) Fetch failure does not crash WalletScreen — omits fee line gracefully without error banner',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    apiClient.shouldFail = true;

    await tester.pumpWidget(buildWalletScreenWidget());
    await tester.pumpAndSettle();

    // Screen should render normal wallet headers without crashing
    expect(find.text('My Wallet'), findsOneWidget);
    expect(find.text('Total Balance'), findsOneWidget);

    // Fee text should be omitted
    expect(find.byKey(const Key('platform_fee_percentage_text')), findsNothing);

    // No error banner should be present
    expect(ownerProvider.error, isNull);
  });
}
