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
import 'package:frontend/models/job.dart';
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

  // Option C: capture the landmark notes bookJob carries.
  int bookJobCalls = 0;
  String? lastPickupNote;
  String? lastDestinationNote;

  @override
  Future<Job?> bookJob({
    required String serviceId,
    required String userId,
    required double latitude,
    required double longitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required String paymentMethod,
    String? pickupAddressNote,
    String? destinationAddressNote,
  }) async {
    bookJobCalls++;
    lastPickupNote = pickupAddressNote;
    lastDestinationNote = destinationAddressNote;
    return Job(
      id: 'job-note-1',
      ownerId: 'tenant-456',
      userId: 'cust-1',
      serviceId: serviceId,
      status: 'pending_dispatch',
      location: JobLocation(latitude: latitude, longitude: longitude),
      destination: JobLocation(
        latitude: destinationLatitude,
        longitude: destinationLongitude,
        addressNote: destinationAddressNote,
      ),
      paymentMethod: paymentMethod,
    );
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

  testWidgets(
      'Service card parses and renders working hours + coverage radius profile fields',
      (WidgetTester tester) async {
    // 1. fromJson parses the backend-shaped payload (fields live on the
    // embedded Service alongside distance_km/final_price).
    final parsed = MarketplaceService.fromJson({
      'id': 'srv-1',
      'tenant_id': 'tenant-1',
      'name': 'Express Delivery',
      'category': 'delivery',
      'base_price': 20.0,
      'tenant_base_price': 20.0,
      'tenant_price_per_km': 3.5,
      'latitude': 30.0444,
      'longitude': 31.2357,
      'working_hours': '9am-5pm',
      'coverage_radius_km': 25.0,
      'address': 'Downtown Cairo',
      'photo_url': 'https://example.com/photo.png',
      'distance_km': 4.2,
      'final_price': 35.0,
    });
    expect(parsed.workingHours, equals('9am-5pm'));
    expect(parsed.coverageRadiusKm, equals(25.0));
    expect(parsed.address, equals('Downtown Cairo'));
    expect(parsed.photoUrl, equals('https://example.com/photo.png'));

    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    mockMarketplaceProvider.mockServices = [
      MarketplaceService(
        id: 'srv-1',
        tenantId: 'tenant-1',
        name: 'Express Delivery',
        category: 'delivery',
        basePrice: 20.0,
        tenantBasePrice: 20.0,
        tenantPricePerKM: 3.5,
        latitude: 30.0444,
        longitude: 31.2357,
        distanceKM: 4.2,
        finalPrice: 35.0,
        workingHours: '9am-5pm',
        coverageRadiusKm: 25.0,
        address: 'Downtown Cairo',
        photoUrl: 'https://example.com/photo.png',
      ),
      MarketplaceService(
        id: 'srv-2',
        tenantId: 'tenant-2',
        name: 'Budget Ride',
        category: 'transport',
        basePrice: 10.0,
        tenantBasePrice: 10.0,
        tenantPricePerKM: 2.0,
        latitude: 30.0444,
        longitude: 31.2357,
        distanceKM: 1.1,
        finalPrice: 12.0,
      ),
    ];

    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // 2. Profile fields render on the configured card only.
    expect(find.byKey(const Key('service_working_hours_text')), findsOneWidget);
    expect(find.text('Hours: 9am-5pm'), findsOneWidget);
    expect(
        find.byKey(const Key('service_coverage_radius_text')), findsOneWidget);
    expect(find.text('Coverage: 25.0 km'), findsOneWidget);

    // 3. Zero RenderFlex overflow on the default viewport.
    expect(tester.takeException(), isNull);
  });

  MarketplaceService outOfServiceCard({
    required String id,
    required String name,
    bool? isOpenNow,
    String? reopensAt,
  }) {
    return MarketplaceService(
      id: id,
      tenantId: 'tenant-$id',
      name: name,
      category: 'delivery',
      basePrice: 20.0,
      tenantBasePrice: 20.0,
      tenantPricePerKM: 3.5,
      latitude: 30.0444,
      longitude: 31.2357,
      distanceKM: 4.2,
      finalPrice: 35.0,
      isOpenNow: isOpenNow,
      reopensAt: reopensAt == null ? null : DateTime.parse(reopensAt),
    );
  }

  testWidgets(
      'Out-of-service badge renders exact copy when reopens_at is absent',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    mockMarketplaceProvider.mockServices = [
      outOfServiceCard(id: 'srv-closed', name: 'Night Owl Delivery'),
    ];
    // fromJson parses explicit false + explicit null like the backend sends.
    final parsed = MarketplaceService.fromJson({
      'id': 'srv-closed',
      'tenant_id': 'tenant-x',
      'name': 'Night Owl Delivery',
      'category': 'delivery',
      'is_open_now': false,
      'reopens_at': null,
      'distance_km': 1.0,
      'final_price': 10.0,
    });
    expect(parsed.isOpenNow, isFalse);
    expect(parsed.reopensAt, isNull);

    mockMarketplaceProvider.mockServices = [
      outOfServiceCard(
          id: 'srv-closed', name: 'Night Owl Delivery', isOpenNow: false),
    ];
    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('service_out_of_service_badge')), findsOneWidget);
    final badgeText = tester
        .widget<Text>(find.byKey(const Key('service_out_of_service_text')));
    expect(badgeText.data, equals('Out of Service'));
    // Rest of the card stays intact; Book is NOT disabled client-side.
    expect(find.text('Night Owl Delivery'), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Book'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Out-of-service badge appends reopening time when available',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    final parsed = MarketplaceService.fromJson({
      'id': 'srv-closed-2',
      'tenant_id': 'tenant-y',
      'name': 'Early Bird Delivery',
      'category': 'delivery',
      'is_open_now': false,
      'reopens_at': '2030-06-15T10:00:00Z',
      'distance_km': 1.0,
      'final_price': 10.0,
    });
    expect(parsed.isOpenNow, isFalse);
    expect(parsed.reopensAt, isNotNull);

    mockMarketplaceProvider.mockServices = [
      outOfServiceCard(
        id: 'srv-closed-2',
        name: 'Early Bird Delivery',
        isOpenNow: false,
        reopensAt: '2030-06-15T10:00:00Z',
      ),
    ];
    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('service_out_of_service_badge')), findsOneWidget);
    final badgeText = tester
        .widget<Text>(find.byKey(const Key('service_out_of_service_text')));
    final text = badgeText.data ?? '';
    expect(text.startsWith('Out of Service — opens '), isTrue,
        reason: 'badge must append reopening time, got: $text');
    expect(text.length > 'Out of Service — opens '.length, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No badge renders for unknown (null) or open schedules',
      (WidgetTester tester) async {
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );

    final parsed = MarketplaceService.fromJson({
      'id': 'srv-plain',
      'tenant_id': 'tenant-z',
      'name': 'Plain Delivery',
      'category': 'delivery',
      'distance_km': 1.0,
      'final_price': 10.0,
    });
    expect(parsed.isOpenNow, isNull);
    expect(parsed.reopensAt, isNull);

    mockMarketplaceProvider.mockServices = [
      outOfServiceCard(id: 'srv-plain', name: 'Plain Delivery'),
      outOfServiceCard(id: 'srv-open', name: 'Open Delivery', isOpenNow: true),
    ];
    await tester.pumpWidget(buildMarketplaceApp(
      MockAuthProviderForTest(apiClient, customerUser),
    ));
    await tester.pumpAndSettle();

    // Services look exactly as before this feature: no badge anywhere.
    expect(find.byKey(const Key('service_out_of_service_badge')), findsNothing);
    expect(find.byKey(const Key('service_out_of_service_text')), findsNothing);
    expect(find.text('Plain Delivery'), findsOneWidget);
    expect(find.text('Open Delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Option C: destination landmark note flows picker -> confirmation -> bookJob',
      (WidgetTester tester) async {
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

    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Booking'), findsOneWidget);

    // Destination picker carries the optional note field ...
    await tester.tap(find.byKey(const Key('choose_destination_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('destination_location_picker_dialog')),
        findsOneWidget);
    expect(find.byKey(const Key('location_picker_note_field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('location_picker_note_field')),
        "beside Ahmed's kiosk");
    // Unfocus: a focused field's cursor blink defeats pumpAndSettle.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester
        .tap(find.byKey(const Key('confirm_destination_location_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pumpAndSettle();

    // ... confirmation shows the typed note instead of raw coordinates ...
    expect(
        find.byKey(const Key('booking_destination_note_text')), findsOneWidget);
    expect(find.text("beside Ahmed's kiosk"), findsOneWidget);
    expect(
        find.byKey(const Key('booking_destination_coords_text')), findsNothing);
    expect(find.byKey(const Key('booking_destination_minimap')), findsNothing);

    // ... and booking carries the note to the backend payload.
    // (Fixed-frame pumps: success navigates to the polling JobStatusScreen,
    // whose periodic timers defeat pumpAndSettle by design.)
    await tester.tap(find.byKey(const Key('confirm_booking_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(mockMarketplaceProvider.bookJobCalls, 1);
    expect(mockMarketplaceProvider.lastDestinationNote, "beside Ahmed's kiosk");
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Option C: destination without note shows mini-map plus add affordance',
      (WidgetTester tester) async {
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

    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();

    // Pick destination WITHOUT typing a note.
    await tester.tap(find.byKey(const Key('choose_destination_button')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('confirm_destination_location_button')));
    await tester.pumpAndSettle();

    // Spatial preview beats raw numbers; add-note affordance offered.
    expect(
        find.byKey(const Key('booking_destination_minimap')), findsOneWidget);
    expect(
        find.byKey(const Key('booking_destination_coords_text')), findsNothing);
    expect(
        find.byKey(const Key('add_destination_note_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
