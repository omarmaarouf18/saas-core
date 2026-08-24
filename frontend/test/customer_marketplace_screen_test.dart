import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:frontend/widgets/themed_error_banner.dart';

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
  }

  @override
  Future<Map<String, dynamic>> fetchRatings(String tenantId) async {
    return {'average': 4.8, 'count': 25};
  }
}

void main() {
  late ApiClient apiClient;
  late MockMarketplaceProviderForTest mockMarketplaceProvider;

  setUp(() {
    apiClient = ApiClient();
    mockMarketplaceProvider = MockMarketplaceProviderForTest(apiClient);
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

    // 3. Toggle switch ON
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // 4. Verify fetchServices was called with nearBy = true
    expect(mockMarketplaceProvider.lastFetchNearBy, isTrue);
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
            "Note: Escrow payments and wallet deductions are currently deferred for this beta launch."),
        findsOneWidget);
    expect(find.byKey(const Key('confirm_booking_button')), findsOneWidget);
    expect(find.text("Cancel"), findsOneWidget);

    // Verify zero RenderFlex overflow
    expect(tester.takeException(), isNull);
  });
}
