import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/screens/customer_home_screen.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/marketplace_service.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  UserProfile? user = UserProfile(
    id: 'user-cust-123',
    email: 'customer@example.com',
    username: 'Jane Customer',
    role: 'user',
    kycStatus: 'approved',
  );

  @override
  String? token = 'mock-user-jwt';

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchUserProfile() async {}

  @override
  Future<void> logout() async {}

  Future<void> updateProfile({
    String? username,
    String? phone,
    List<String>? frequentAddresses,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockMarketplaceProvider extends ChangeNotifier
    implements MarketplaceProvider {
  @override
  List<MarketplaceService> services = [];

  @override
  List<Job> customerJobs = [];

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchServices({
    bool nearBy = false,
    double lat = 0,
    double lon = 0,
    double radius = 50,
    String sortBy = 'none',
  }) async {}

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async {
    return customerJobs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockNotificationsProvider extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 2;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockThemeProvider extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;

  bool isDarkMode = false;

  String currentLanguage = 'en';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createTestApp({Widget? child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => MockAuthProvider()),
      ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => MockMarketplaceProvider()),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => MockNotificationsProvider()),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => MockThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => MockChatProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child ?? const CustomerHomeScreen(),
    ),
  );
}

void main() {
  testWidgets('CustomerHomeScreen renders 4-tab bottom navigation bar',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 0)));
    await tester.pump(const Duration(milliseconds: 100));

    // Verify 4 bottom navigation tabs are rendered
    expect(find.byKey(const Key('customer_bottom_navigation_bar')),
        findsOneWidget);
    expect(find.byKey(const Key('nav_tab_home')), findsOneWidget);
    expect(find.byKey(const Key('nav_tab_services')), findsOneWidget);
    expect(find.byKey(const Key('nav_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('nav_tab_settings')), findsOneWidget);

    // Verify Home tab initial content
    expect(find.text('Welcome back, Jane Customer!'), findsOneWidget);
    expect(find.byKey(const Key('category_tile_delivery')), findsOneWidget);
    expect(find.byKey(const Key('category_tile_transport')), findsOneWidget);
    expect(find.byKey(const Key('category_tile_shipping')), findsOneWidget);
    expect(find.byKey(const Key('category_tile_all')), findsOneWidget);
  });

  testWidgets('CustomerHomeScreen initialTabIndex 1 renders Services tab',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 1)));
    await tester.pump();

    expect(find.byType(CustomerMarketplaceScreen), findsOneWidget);
  });

  testWidgets('CustomerHomeScreen initialTabIndex 2 renders History tab',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 2)));
    await tester.pump();

    expect(find.byType(CustomerJobsScreen), findsOneWidget);
  });

  testWidgets('CustomerHomeScreen initialTabIndex 3 renders Settings tab',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 3)));
    await tester.pump();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
