import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile _user;

  MockAuthProviderForTest(super.apiClient, this._user);

  @override
  UserProfile? get user => _user;

  @override
  String? get token => "mock-token";
}

class MockMarketplaceProviderForTest extends MarketplaceProvider {
  MockMarketplaceProviderForTest(super.apiClient);

  @override
  List<MarketplaceService> get services => [];

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
  }) async {}
}

void main() {
  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  Widget buildMarketplaceApp(AuthProvider authProvider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => MockMarketplaceProviderForTest(apiClient),
        ),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient),
        ),
      ],
      child: const MaterialApp(
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
    final mapBtn = find.byKey(const Key('choose_location_map_button'));
    expect(mapBtn, findsOneWidget);
    expect(find.text("30.0444, 31.2357"), findsOneWidget);

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
}
