import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/service_screen.dart';

class MockAuthProviderForServiceTest extends AuthProvider {
  MockAuthProviderForServiceTest(super.apiClient);

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

class MockOwnerProviderForServiceTest extends OwnerProvider {
  final String? testError;
  int fetchServicesCalls = 0;

  MockOwnerProviderForServiceTest(super.apiClient, {this.testError});

  @override
  String? get error => testError;

  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get services => [];

  @override
  Future<void> fetchServices() async {
    fetchServicesCalls++;
  }
}

Widget createServiceTestWidget({
  required MockAuthProviderForServiceTest authProvider,
  required MockOwnerProviderForServiceTest ownerProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: ServiceScreen(),
    ),
  );
}

void main() {
  testWidgets('ServiceScreen error banner renders when ownerProvider.error is set',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForServiceTest(apiClient);
    final owner = MockOwnerProviderForServiceTest(
      apiClient,
      testError: 'Failed to load services. Network unreachable.',
    );

    await tester.pumpWidget(createServiceTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('service_screen_error')), findsOneWidget);
    expect(find.text('Failed to load services. Network unreachable.'),
        findsOneWidget);
  });

  testWidgets(
      'ServiceScreen error banner is absent on successful load (error is null)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForServiceTest(apiClient);
    final owner = MockOwnerProviderForServiceTest(apiClient);

    await tester.pumpWidget(createServiceTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('service_screen_error')), findsNothing);
  });

  testWidgets('Tapping retry on ServiceScreen error banner re-triggers fetch',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProviderForServiceTest(apiClient);
    final owner = MockOwnerProviderForServiceTest(
      apiClient,
      testError: 'Timeout',
    );

    await tester.pumpWidget(createServiceTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    // Screen loads once in initState
    expect(owner.fetchServicesCalls, equals(1));

    final retryButton = find.descendant(
      of: find.byKey(const Key('service_screen_error')),
      matching: find.byType(TextButton),
    );
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(owner.fetchServicesCalls, equals(2));
  });
}
