import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/subscription_screen.dart';
import 'package:frontend/widgets/themed_banner.dart';
import 'package:frontend/widgets/themed_card.dart';

class MockAuthProvider extends AuthProvider {
  MockAuthProvider(super.apiClient);

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

class MockOwnerProvider extends OwnerProvider {
  String _currentTier;
  bool updateSubscriptionCalled = false;
  String? lastRequestedTier;

  MockOwnerProvider(super.apiClient, {String initialTier = 'free'})
      : _currentTier = initialTier;

  @override
  String get subscriptionTier => _currentTier;

  void setTier(String tier) {
    _currentTier = tier;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> updateSubscription({
    required String tenantId,
    required String tier,
  }) async {
    updateSubscriptionCalled = true;
    lastRequestedTier = tier;
    _currentTier = tier;
    notifyListeners();
    return {'message': 'Subscription updated successfully!'};
  }
}

Widget createSubscriptionTestWidget({
  required MockAuthProvider authProvider,
  required MockOwnerProvider ownerProvider,
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
      home: SubscriptionScreen(),
    ),
  );
}

void main() {
  testWidgets(
      '(a) Free tier renders Free as active and Professional as recommended highlighted card',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProvider(apiClient);
    final owner = MockOwnerProvider(apiClient, initialTier: 'free');

    await tester.pumpWidget(createSubscriptionTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    // Verify current plan header
    expect(find.text('YOUR CURRENT PLAN'), findsOneWidget);
    expect(find.text('FREE'), findsOneWidget);

    // Verify plans listed
    expect(find.text('RECOMMENDED'), findsOneWidget);
    expect(find.text('Active Plan'), findsOneWidget);
    expect(find.text('Upgrade to Professional'), findsOneWidget);

    // Verify highlighted card variant exists
    final cards = tester.widgetList<ThemedCard>(find.byType(ThemedCard));
    expect(
      cards.any((c) => c.variant == ThemedCardVariant.highlighted),
      isTrue,
    );
  });

  testWidgets(
      '(b) Pending payment tier renders ThemedWarningBanner with activation message',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProvider(apiClient);
    final owner = MockOwnerProvider(apiClient, initialTier: 'pending_payment');

    await tester.pumpWidget(createSubscriptionTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    expect(find.text('PENDING PAYMENT'), findsOneWidget);
    expect(find.byType(ThemedWarningBanner), findsOneWidget);
    expect(
      find.text(
          'Pending activation. Please contact support to complete payment.'),
      findsOneWidget,
    );
    expect(find.text('Awaiting Payment'), findsOneWidget);
  });

  testWidgets(
      '(c) Paid tier renders Professional as active and enables Downgrade button',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProvider(apiClient);
    final owner = MockOwnerProvider(apiClient, initialTier: 'paid');

    await tester.pumpWidget(createSubscriptionTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    expect(find.text('PAID'), findsOneWidget);
    expect(find.text('Downgrade to Free'), findsOneWidget);
    expect(find.text('Active Plan'), findsOneWidget);
  });

  testWidgets('(d) Tapping Upgrade to Professional triggers subscription update',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final auth = MockAuthProvider(apiClient);
    final owner = MockOwnerProvider(apiClient, initialTier: 'free');

    await tester.pumpWidget(createSubscriptionTestWidget(
      authProvider: auth,
      ownerProvider: owner,
    ));
    await tester.pumpAndSettle();

    final upgradeBtn = find.text('Upgrade to Professional');
    await tester.ensureVisible(upgradeBtn);
    await tester.pumpAndSettle();

    await tester.tap(upgradeBtn);
    await tester.pumpAndSettle();

    expect(owner.updateSubscriptionCalled, isTrue);
    expect(owner.lastRequestedTier, 'paid');
  });
}
