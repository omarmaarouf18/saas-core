import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
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
import 'package:frontend/widgets/location_picker_map.dart';

class MockGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission initialPermission = LocationPermission.denied;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Position mockPosition = Position(
    latitude: 31.2001,
    longitude: 29.9187,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => initialPermission;

  @override
  Future<LocationPermission> requestPermission() async => requestedPermission;

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      mockPosition;
}

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
  // Audit C2/C3: ChatProvider grew isLoadingHistory; implements-mocks must
  // declare it or chat-screen reads crash via noSuchMethod.
  @override
  bool isLoadingHistory = false;

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

  testWidgets(
      'Tapping quick access category tile switches to Services tab with debounce protection',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 0)));
    await tester.pump(const Duration(milliseconds: 100));

    final deliveryTile = find.byKey(const Key('category_tile_delivery'));
    expect(deliveryTile, findsOneWidget);

    // Rapid double-tap to verify debounce guard
    await tester.tap(deliveryTile);
    await tester.tap(deliveryTile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify switched to Services tab
    expect(find.byType(CustomerMarketplaceScreen), findsOneWidget);
  });

  testWidgets(
      'Tapping home location card fetches real GPS coordinates and initializes picker with them',
      (WidgetTester tester) async {
    final mockGeolocator = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mockGeolocator;

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 0)));
    await tester.pump(const Duration(milliseconds: 100));

    final locationCard = find.byKey(const Key('home_quick_search_card'));
    expect(locationCard, findsOneWidget);

    await tester.tap(locationCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_search_location_picker_dialog')),
        findsOneWidget);

    final pickerMapFinder = find.byType(LocationPickerMap);
    expect(pickerMapFinder, findsOneWidget);
    final pickerMap = tester.widget<LocationPickerMap>(pickerMapFinder);
    expect(pickerMap.initialLocation!.latitude, equals(31.2001));
    expect(pickerMap.initialLocation!.longitude, equals(29.9187));

    // Confirm location navigates to Services tab
    final confirmBtn = find.byKey(const Key('confirm_search_location_button'));
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMarketplaceScreen), findsOneWidget);
  });

  testWidgets(
      'Tapping home location card falls back to Cairo default when permission denied',
      (WidgetTester tester) async {
    final mockGeolocator = MockGeolocatorPlatform();
    mockGeolocator.isServiceEnabled = false;
    GeolocatorPlatform.instance = mockGeolocator;

    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
        createTestApp(child: const CustomerHomeScreen(initialTabIndex: 0)));
    await tester.pump(const Duration(milliseconds: 100));

    final locationCard = find.byKey(const Key('home_quick_search_card'));
    await tester.tap(locationCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_search_location_picker_dialog')),
        findsOneWidget);

    final pickerMapFinder = find.byType(LocationPickerMap);
    expect(pickerMapFinder, findsOneWidget);
    final pickerMap = tester.widget<LocationPickerMap>(pickerMapFinder);
    expect(pickerMap.initialLocation!.latitude,
        equals(LocationPickerMap.cairoDefault.latitude));
    expect(pickerMap.initialLocation!.longitude,
        equals(LocationPickerMap.cairoDefault.longitude));
  });

  group('C1 activity loading state (three distinct states)', () {
    Future<void> pumpHome(
        WidgetTester tester, MockMarketplaceProvider marketplace) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => MockAuthProvider()),
          ChangeNotifierProvider<MarketplaceProvider>.value(value: marketplace),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => MockNotificationsProvider()),
          ChangeNotifierProvider<ThemeProvider>(
              create: (_) => MockThemeProvider()),
          ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider()),
          ChangeNotifierProvider<ChatProvider>(
              create: (_) => MockChatProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const CustomerHomeScreen(initialTabIndex: 0),
        ),
      ));
      // NOTE: no pumpAndSettle here — the loading skeleton (like every
      // SkeletonLoader shimmer) animates forever, so settle would time out.
      // Fixed pumps flush the post-frame fetch + provider rebuilds.
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    Job activeJobFixture() => Job(
          id: 'job-active-1',
          ownerId: 'owner-1',
          employeeId: 'emp-1',
          userId: 'user-cust-123',
          serviceId: 'svc-1',
          status: 'active',
          location: JobLocation(latitude: 30.0, longitude: 31.0),
          paymentMethod: 'cod',
        );

    testWidgets('loading with no cached jobs shows skeleton, not empty card',
        (WidgetTester tester) async {
      final marketplace = MockMarketplaceProvider()..isLoading = true;
      await pumpHome(tester, marketplace);

      // Loading render: skeleton present...
      expect(find.byKey(const Key('customer_home_activity_skeleton')),
          findsOneWidget);
      // ...genuine-empty card absent (previously it flashed here — C1)...
      expect(find.text('No Orders Found'), findsNothing);
      // ...and no error banner either.
      expect(
          find.byKey(const Key('customer_home_activity_error')), findsNothing);
    });

    testWidgets('loaded empty shows the empty card, never the skeleton',
        (WidgetTester tester) async {
      final marketplace = MockMarketplaceProvider()..isLoading = false;
      await pumpHome(tester, marketplace);

      expect(find.text('No Orders Found'), findsOneWidget);
      expect(find.byKey(const Key('customer_home_activity_skeleton')),
          findsNothing);
      expect(
          find.byKey(const Key('customer_home_activity_error')), findsNothing);
    });

    testWidgets('error takes precedence over loading (banner, no skeleton)',
        (WidgetTester tester) async {
      final marketplace = MockMarketplaceProvider()
        ..isLoading = true
        ..error = 'Service temporarily unavailable';
      await pumpHome(tester, marketplace);

      expect(find.byKey(const Key('customer_home_activity_error')),
          findsOneWidget);
      expect(find.byKey(const Key('customer_home_activity_skeleton')),
          findsNothing);
      expect(find.text('No Orders Found'), findsNothing);
    });

    testWidgets('cached jobs keep rendering during refresh (no skeleton)',
        (WidgetTester tester) async {
      final marketplace = MockMarketplaceProvider()
        ..isLoading = true
        ..customerJobs = [activeJobFixture()];
      await pumpHome(tester, marketplace);

      expect(find.byKey(const Key('customer_home_activity_skeleton')),
          findsNothing);
      expect(find.textContaining('QD-JOB-ACT'), findsOneWidget);
    });
  });
}
