import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/wallet_screen.dart';
import 'package:provider/provider.dart';

/// F2 (fee-line removal): the wallet no longer fetches or renders platform
/// config. These tests pin the removal — no fee line under any backend
/// response, and the internal `platform_wallet_id` secret never rendered —
/// rather than the old fee-rendering contract.
class MockApiClientForConfigTest extends ApiClient {
  Map<String, dynamic> mockConfigResponse = {
    'id': 'config-global-1',
    'platform_fee_percentage': 5.0,
    'platform_wallet_id': 'SECRET_INTERNAL_WALLET_ID_9999',
  };

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (endpoint == '/users/platform/config') {
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

  testWidgets(
      '(F2) WalletScreen renders with no platform-fee line even when the backend still serves config',
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

    // No fee line under any backend response.
    expect(find.byKey(const Key('platform_fee_percentage_text')), findsNothing);
    expect(find.textContaining('Platform fee'), findsNothing);
    expect(find.textContaining('نسبة المنصة'), findsNothing);

    // Security assertion: platform_wallet_id string must NEVER be rendered.
    expect(find.textContaining('SECRET_INTERNAL_WALLET_ID_9999'), findsNothing);
    expect(find.textContaining('platform_wallet_id'), findsNothing);

    // The wallet itself still renders.
    expect(find.text('My Wallet'), findsOneWidget);
  });

  testWidgets('(F2) Zero-commission backend (0.0%) also renders no fee line',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    apiClient.mockConfigResponse = {
      'id': 'config-global-1',
      'platform_fee_percentage': 0.0,
      'platform_wallet_id': 'platform-central',
    };

    await tester.pumpWidget(buildWalletScreenWidget());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('platform_fee_percentage_text')), findsNothing);
    expect(find.text('Platform fee: 0%'), findsNothing);
    expect(find.text('My Wallet'), findsOneWidget);
  });
}
