import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/themed_error_banner.dart';

class MockGeolocatorPlatformForMarketplace extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission initialPermission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  Completer<Position>? positionCompleter;
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
      {LocationSettings? locationSettings}) async {
    if (positionCompleter != null) {
      return positionCompleter!.future;
    }
    return mockPosition;
  }
}

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile _user;

  MockAuthProviderForTest(super.apiClient, this._user);

  @override
  UserProfile? get user => _user;

  @override
  String? get token => "mock-token";
}

class MockMarketplaceProviderForTest extends MarketplaceProvider {
  bool? lastFetchNearBy;
  double? lastFetchRadius;
  List<MarketplaceService> mockServices = [];

  MockMarketplaceProviderForTest(super.apiClient);

  @override
  List<MarketplaceService> get services => mockServices;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchServices({
    bool nearBy = true,
    double lat = 30.0444,
    double lon = 31.2357,
    double radius = 50.0,
    String sortBy = 'price',
  }) async {
    lastFetchNearBy = nearBy;
    lastFetchRadius = radius;
  }

  @override
  Future<Map<String, dynamic>> fetchRatings(String tenantId) async {
    return {'average': 4.8, 'count': 25};
  }
}

void main() {
  late ApiClient apiClient;
  late MockMarketplaceProviderForTest mockMarketplaceProvider;
  late MockGeolocatorPlatformForMarketplace mockGeolocator;

  setUp(() {
    apiClient = ApiClient();
    mockMarketplaceProvider = MockMarketplaceProviderForTest(apiClient);
    mockGeolocator = MockGeolocatorPlatformForMarketplace();
    GeolocatorPlatform.instance = mockGeolocator;
  });

  Widget buildMarketplaceApp(AuthProvider authProvider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<MarketplaceProvider>.value(
          value: mockMarketplaceProvider,
        ),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CustomerMarketplaceScreen(),
      ),
    );
  }

  testWidgets(
      'Removed Latitude/Longitude text inputs and opens LocationPickerMap dialog',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // 1. Verify legacy text fields for Latitude and Longitude are GONE
    expect(find.widgetWithText(TextField, "Latitude"), findsNothing);
    expect(find.widgetWithText(TextField, "Longitude"), findsNothing);

    // 2. Verify Map Picker button exists
    await tester.tap(find.byKey(const Key('marketplace_filters_button')));
    await tester.pumpAndSettle();
    final mapBtn = find.byKey(const Key('choose_location_map_button'));
    expect(mapBtn, findsOneWidget);
    expect(find.text("Choose Location on Map"), findsOneWidget);

    // 3. Tap Map Picker button to open Location Picker Dialog
    await tester.tap(mapBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsOneWidget);
    expect(find.text("Choose Search Location"), findsOneWidget);

    // 4. Tap Confirm Location button to close dialog
    final confirmBtn = find.byKey(const Key('confirm_location_button'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsNothing);
  });

  testWidgets(
      'LocationPickerMap dialog renders overflow-free on narrow 360x800 mobile viewport',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('marketplace_filters_button')));
    await tester.pumpAndSettle();
    final mapBtn = find.byKey(const Key('choose_location_map_button'));
    expect(mapBtn, findsOneWidget);
    await tester.tap(mapBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsOneWidget);
    expect(find.text("Choose Search Location"), findsOneWidget);

    final confirmBtn = find.byKey(const Key('confirm_location_button'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsNothing);
  });

  testWidgets(
      'Defaults to nearBy: false and toggling distance filter switch sets nearBy: true',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // 1. Verify fetchServices was called with nearBy = false by default
    expect(mockMarketplaceProvider.lastFetchNearBy, isFalse);

    // 2. Verify nearby filter switch exists
    await tester.tap(find.byKey(const Key('marketplace_filters_button')));
    await tester.pumpAndSettle();
    final switchFinder = find.byKey(const Key('nearby_filter_switch'));
    expect(switchFinder, findsOneWidget);

    // 3. Toggle switch ON — verify sheet remains open (switch still visible)
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearby_filter_switch')), findsOneWidget);

    // 4. Tap Apply Filters — sheet closes and services reload with nearBy = true
    await tester.tap(find.byKey(const Key('apply_filters_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearby_filter_switch')), findsNothing);
    expect(mockMarketplaceProvider.lastFetchNearBy, isTrue);
  });

  testWidgets(
      'FiltersSheet stays open across combined toggle and radius changes until Apply is pressed',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // Open filters sheet
    await tester.tap(find.byKey(const Key('marketplace_filters_button')));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('nearby_filter_switch'));
    expect(switchFinder, findsOneWidget);

    // Toggle switch ON
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    // Sheet must remain open
    expect(find.byKey(const Key('nearby_filter_switch')), findsOneWidget);

    // Enter radius
    final radiusFinder = find.byType(TextField);
    expect(radiusFinder, findsOneWidget);
    await tester.enterText(radiusFinder, '25');
    await tester.pumpAndSettle();

    // Sheet still open
    expect(find.byKey(const Key('nearby_filter_switch')), findsOneWidget);

    // Tap Apply Filters
    await tester.tap(find.byKey(const Key('apply_filters_button')));
    await tester.pumpAndSettle();

    // Sheet is now dismissed and services fetched with updated filters
    expect(find.byKey(const Key('nearby_filter_switch')), findsNothing);
    expect(mockMarketplaceProvider.lastFetchNearBy, isTrue);
    expect(mockMarketplaceProvider.lastFetchRadius, equals(25.0));
  });

  testWidgets(
      'BookingDialog renders overflow-free on narrow 360x800 mobile viewport and displays ThemedWarningBanner',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    mockMarketplaceProvider.mockServices = [
      MarketplaceService(
        id: 'srv-123',
        tenantId: 'tenant-456',
        name: 'Express Delivery',
        category: 'delivery',
        basePrice: 20.0,
        tenantBasePrice: 20.0,
        tenantPricePerKM: 3.5,
        latitude: 30.0444,
        longitude: 31.2357,
        distanceKM: 4.2,
        finalPrice: 35.0,
      ),
    ];

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // Tap Book button to open _BookingDialog
    final bookBtn = find.text("Book");
    expect(bookBtn, findsOneWidget);
    await tester.tap(bookBtn);
    await tester.pumpAndSettle();

    // Verify dialog title, content, warning banner, and actions
    expect(find.text("Confirm Booking"), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text("Express Delivery")),
        findsOneWidget);
    expect(find.byType(ThemedWarningBanner), findsOneWidget);
    expect(
        find.text(
            "Estimated price is based on the actual trip distance from pickup to destination."),
        findsOneWidget);
    expect(
        find.text(
            "Select a destination on the map to calculate trip distance and price estimate."),
        findsOneWidget);
    expect(
        find.text(
            "Note: Escrow payments and wallet deductions are currently deferred for this beta launch."),
        findsOneWidget);

    final confirmBtn = find.byKey(const Key('confirm_booking_button'));
    expect(confirmBtn, findsOneWidget);
    // Confirm button is disabled when destination is not set
    final primaryBtnWidget = tester.widget<PrimaryButton>(confirmBtn);
    expect(primaryBtnWidget.onPressed, isNull);

    // Initial trip distance and price show placeholder
    expect(find.byKey(const Key('booking_trip_distance_text')), findsOneWidget);
    expect(find.text(" — "), findsNWidgets(2)); // distance & price placeholders

    // Open destination picker
    final chooseDestBtn = find.byKey(const Key('choose_destination_button'));
    expect(chooseDestBtn, findsOneWidget);
    await tester.tap(chooseDestBtn);
    await tester.pumpAndSettle();

    // Verify destination picker dialog opens
    expect(find.byKey(const Key('destination_location_picker_dialog')),
        findsOneWidget);
    final confirmDestBtn =
        find.byKey(const Key('confirm_destination_location_button'));
    expect(confirmDestBtn, findsOneWidget);
    await tester.tap(confirmDestBtn);
    await tester.pumpAndSettle();

    // Dialog closed, destination set, confirm button now enabled
    expect(find.byKey(const Key('destination_location_picker_dialog')),
        findsNothing);
    final enabledConfirmBtn = tester.widget<PrimaryButton>(confirmBtn);
    expect(enabledConfirmBtn.onPressed, isNotNull);

    expect(find.text("Cancel"), findsOneWidget);

    // Verify zero RenderFlex overflow
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Book button is in loading/disabled state while _isLocating is true, then enables when location resolves',
      (WidgetTester tester) async {
    final mockGeolocator = MockGeolocatorPlatformForMarketplace();
    final completer = Completer<Position>();
    mockGeolocator.positionCompleter = completer;
    GeolocatorPlatform.instance = mockGeolocator;

    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    mockMarketplaceProvider.mockServices = [
      MarketplaceService(
        id: 'srv-123',
        tenantId: 'tenant-456',
        name: 'Express Delivery',
        category: 'delivery',
        basePrice: 20.0,
        tenantBasePrice: 20.0,
        tenantPricePerKM: 3.5,
        latitude: 30.0444,
        longitude: 31.2357,
        distanceKM: 4.2,
        finalPrice: 35.0,
      ),
    ];

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    // Pump a frame so postFrameCallback triggers _initLocation()
    await tester.pump();

    // 1. _initLocation is waiting for completer. PrimaryButton must be loading.
    final bookButtonFinder = find.widgetWithText(PrimaryButton, 'Book');
    expect(bookButtonFinder, findsNothing);
    final primaryBtnFinder = find.byType(PrimaryButton);
    expect(primaryBtnFinder, findsOneWidget);
    final primaryBtn = tester.widget<PrimaryButton>(primaryBtnFinder);
    expect(primaryBtn.isLoading, isTrue);
    expect(primaryBtn.onPressed, isNull);

    // 2. Resolve GPS position
    completer.complete(mockGeolocator.mockPosition);
    await tester.pumpAndSettle();

    // 3. Button is now enabled with "Book" text
    expect(find.widgetWithText(PrimaryButton, 'Book'), findsOneWidget);
    final enabledBtn = tester.widget<PrimaryButton>(primaryBtnFinder);
    expect(enabledBtn.isLoading, isFalse);
    expect(enabledBtn.onPressed, isNotNull);
  });

  testWidgets('setCustomerLocation resets _isLocating to false',
      (WidgetTester tester) async {
    final mockGeolocator = MockGeolocatorPlatformForMarketplace();
    final completer = Completer<Position>();
    mockGeolocator.positionCompleter = completer;
    GeolocatorPlatform.instance = mockGeolocator;

    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    mockMarketplaceProvider.mockServices = [
      MarketplaceService(
        id: 'srv-123',
        tenantId: 'tenant-456',
        name: 'Express Delivery',
        category: 'delivery',
        basePrice: 20.0,
        tenantBasePrice: 20.0,
        tenantPricePerKM: 3.5,
        latitude: 30.0444,
        longitude: 31.2357,
        distanceKM: 4.2,
        finalPrice: 35.0,
      ),
    ];

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pump();

    // Verify loading initially
    final primaryBtnFinder = find.byType(PrimaryButton);
    expect(tester.widget<PrimaryButton>(primaryBtnFinder).isLoading, isTrue);

    // Call setCustomerLocation directly via state
    final state = tester.state<CustomerMarketplaceScreenState>(
        find.byType(CustomerMarketplaceScreen));
    state.setCustomerLocation(31.2001, 29.9187);
    await tester.pump();

    // Verify button is now loaded and enabled
    expect(tester.widget<PrimaryButton>(primaryBtnFinder).isLoading, isFalse);
    expect(find.widgetWithText(PrimaryButton, 'Book'), findsOneWidget);

    // Complete completer to avoid dangling future
    completer.complete(mockGeolocator.mockPosition);
    await tester.pumpAndSettle();
  });
}
