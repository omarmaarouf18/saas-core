import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/employee_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/owner_history_screen.dart';
import 'package:frontend/screens/wallet_screen.dart';
import 'package:frontend/screens/service_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/job.dart';

class MockAuthProviderForTest extends AuthProvider {
  MockAuthProviderForTest(super.apiClient);

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

  @override
  Future<bool> fetchUserProfile() async => true;
}

class MockOwnerProviderForTest extends OwnerProvider {
  MockOwnerProviderForTest(super.apiClient);

  @override
  double get walletBalance => 500.0;

  @override
  String get subscriptionTier => 'paid';

  @override
  bool get isLoading => false;

  @override
  List<Job> get ownerJobs => [];

  @override
  Future<void> fetchDashboardData(String ownerToken) async {}

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {}

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async => [];
}

class MockMarketplaceProviderForTest extends MarketplaceProvider {
  MockMarketplaceProviderForTest(super.apiClient);

  @override
  List<Job> get customerJobs => [];

  @override
  Future<Map<String, dynamic>> fetchRatings(String token) async {
    return {'average_rating': 4.8, 'count': 25};
  }

  @override
  Future<List<Job>> fetchCustomerJobs([String? token]) async => [];
}

class MockNotificationsProviderForTest extends NotificationsProvider {
  MockNotificationsProviderForTest(super.apiClient);

  @override
  int get unreadCount => 0;

  void connect(String token) {}

  void disconnect() {}
}

class MockThemeProviderForTest extends ThemeProvider {
  @override
  ThemeMode get themeMode => ThemeMode.light;
}

Widget createOwnerHomeScreenApp({int initialTabIndex = 0}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => MockAuthProviderForTest(apiClient)),
      ChangeNotifierProvider<OwnerProvider>(
          create: (_) => MockOwnerProviderForTest(apiClient)),
      ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => MockMarketplaceProviderForTest(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => MockNotificationsProviderForTest(apiClient)),
      ChangeNotifierProvider<ThemeProvider>(
          create: (_) => MockThemeProviderForTest()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(initialTabIndex: initialTabIndex),
    ),
  );
}

void main() {
  testWidgets('HomeScreen renders 4-tab NavigationBar for owner role',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('owner_bottom_navigation_bar')), findsOneWidget);
    expect(find.byKey(const Key('owner_nav_tab_home')), findsOneWidget);
    expect(find.byKey(const Key('owner_nav_tab_employees')), findsOneWidget);
    expect(find.byKey(const Key('owner_nav_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('owner_nav_tab_settings')), findsOneWidget);

    final navBar = tester.widget<NavigationBar>(
        find.byKey(const Key('owner_bottom_navigation_bar')));
    expect(navBar.destinations.length, equals(4));
    expect(
      (navBar.destinations.last as NavigationDestination).key,
      equals(const Key('owner_nav_tab_settings')),
    );

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Employees'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('Tapping bottom nav tabs switches screens',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    // Tab 0: Home Dashboard
    expect(find.text('Quick Delivery Owner Dashboard'), findsOneWidget);
    expect(
        find.byKey(const Key('owner_dashboard_wallet_card')), findsOneWidget);

    // Tap Employees tab (index 1)
    await tester.tap(find.byKey(const Key('owner_nav_tab_employees')));
    await tester.pumpAndSettle();
    expect(find.text('Manage Workers'), findsAtLeastNWidgets(1));
    expect(find.byType(EmployeeScreen), findsOneWidget);

    // Tap History tab (index 2)
    await tester.tap(find.byKey(const Key('owner_nav_tab_history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_tab_activity')), findsOneWidget);
    expect(find.byType(OwnerHistoryScreen), findsOneWidget);

    // Tap Settings tab (index 3)
    await tester.tap(find.byKey(const Key('owner_nav_tab_settings')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('initialTabIndex 1 renders Employees tab directly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 1));
    await tester.pumpAndSettle();

    expect(find.text('Manage Workers'), findsAtLeastNWidgets(1));
    expect(find.byType(EmployeeScreen), findsOneWidget);
  });

  testWidgets('initialTabIndex 2 renders History tab directly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 2));
    await tester.pumpAndSettle();

    expect(find.byType(OwnerHistoryScreen), findsOneWidget);
  });

  testWidgets('initialTabIndex 3 renders Settings tab directly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 3));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Home tab dashboard entry point pushes WalletScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    final walletCard = find.byKey(const Key('owner_dashboard_wallet_card'));
    expect(walletCard, findsOneWidget);

    await tester.ensureVisible(walletCard);
    await tester.pumpAndSettle();

    await tester.tap(walletCard);
    await tester.pumpAndSettle();

    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.text('My Wallet'), findsOneWidget);
  });

  testWidgets('Home tab dashboard entry point pushes ServiceScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    final servicesCard = find.byKey(const Key('owner_dashboard_services_card'));
    expect(servicesCard, findsOneWidget);

    await tester.ensureVisible(servicesCard);
    await tester.pumpAndSettle();

    await tester.tap(servicesCard);
    await tester.pumpAndSettle();

    expect(find.byType(ServiceScreen), findsOneWidget);
  });

  testWidgets(
      'Wallet balance badge renders compact balance and pushes WalletScreen on tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    final walletBadge = find.byKey(const Key('owner_dashboard_wallet_badge'));
    expect(walletBadge, findsOneWidget);
    expect(find.text('500.00 Credits'), findsOneWidget);

    await tester.tap(walletBadge);
    await tester.pumpAndSettle();

    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.text('My Wallet'), findsOneWidget);
  });

  testWidgets('Summary card chips render and navigate correctly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner_dashboard_sub_chip')), findsOneWidget);
    expect(find.byKey(const Key('owner_dashboard_employees_chip')),
        findsOneWidget);
    expect(
        find.byKey(const Key('owner_dashboard_escrow_chip')), findsOneWidget);

    // Tap Employees summary chip -> switches to Employees tab (index 1)
    await tester.tap(find.byKey(const Key('owner_dashboard_employees_chip')));
    await tester.pumpAndSettle();
    expect(find.byType(EmployeeScreen), findsOneWidget);
  });

  testWidgets('IndexedStack preserves visited tab state',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    // Visit Employees tab
    await tester.tap(find.byKey(const Key('owner_nav_tab_employees')));
    await tester.pumpAndSettle();
    expect(find.byType(EmployeeScreen), findsOneWidget);

    // Return to Home tab
    await tester.tap(find.byKey(const Key('owner_nav_tab_home')));
    await tester.pumpAndSettle();

    // Check EmployeeScreen remains mounted in IndexedStack
    final indexedStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(indexedStack.children.length, equals(4));
    expect(indexedStack.index, equals(0));
  });
}
