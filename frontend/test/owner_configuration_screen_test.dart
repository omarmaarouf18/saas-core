import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/screens/owner_configuration_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/user_profile.dart';

class MockAuthProviderForConfigTest extends AuthProvider {
  MockAuthProviderForConfigTest(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-config-1',
        email: 'owner@example.com',
        username: 'config_owner',
        role: 'owner',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-owner-token';

  @override
  Future<bool> fetchUserProfile() async => true;
}

class MockOwnerProviderForConfigTest extends OwnerProvider {
  final List<dynamic> mockServices;
  final String? mockErrorMsg;
  final bool shouldFailUpdate;
  bool updateCalled = false;
  Map<String, dynamic>? lastUpdatePayload;

  MockOwnerProviderForConfigTest(
    super.apiClient, {
    this.mockServices = const [],
    this.mockErrorMsg,
    this.shouldFailUpdate = false,
  });

  @override
  List<dynamic> get services => mockServices;

  @override
  String? get error => mockErrorMsg;

  @override
  Future<void> fetchServices() async {}

  @override
  Future<Map<String, dynamic>> updateOwnerServiceConfig({
    required String serviceId,
    required String ownerId,
    String? name,
    String? category,
    double? tenantBasePrice,
    double? tenantPricePerKM,
    String? photoUrl,
    String? address,
    String? workingHours,
    double? coverageRadiusKm,
  }) async {
    updateCalled = true;
    lastUpdatePayload = {
      'service_id': serviceId,
      'owner_id': ownerId,
      'name': name,
      'category': category,
      'tenant_base_price': tenantBasePrice,
      'tenant_price_per_km': tenantPricePerKM,
      'photo_url': photoUrl,
      'address': address,
      'working_hours': workingHours,
      'coverage_radius_km': coverageRadiusKm,
    };

    if (shouldFailUpdate) {
      throw ApiClientException('Failed to update service config',
          statusCode: 400);
    }
    return {'status': 'success'};
  }
}

Widget createOwnerConfigApp({
  List<dynamic> services = const [],
  bool shouldFailUpdate = false,
  Widget? homeScreen,
}) {
  final apiClient = ApiClient();
  final mockOwnerProvider = MockOwnerProviderForConfigTest(
    apiClient,
    mockServices: services,
    shouldFailUpdate: shouldFailUpdate,
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => MockAuthProviderForConfigTest(apiClient)),
      ChangeNotifierProvider<OwnerProvider>.value(value: mockOwnerProvider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      home: homeScreen ?? const OwnerConfigurationScreen(),
    ),
  );
}

void main() {
  testWidgets('Pre-populates form with existing owner service data',
      (WidgetTester tester) async {
    final existingService = [
      {
        'id': 'svc-999',
        'tenant_id': 'owner-config-1',
        'name': 'Quick Cargo Delivery',
        'category': 'delivery',
        'address': '456 Express Way',
        'working_hours': '8:00 AM - 8:00 PM',
        'coverage_radius_km': 30.0,
        'tenant_base_price': 15.0,
        'tenant_price_per_km': 2.5,
        'photo_url': 'https://example.com/logo.png',
      }
    ];

    await tester.pumpWidget(createOwnerConfigApp(services: existingService));
    await tester.pumpAndSettle();

    expect(find.text('Quick Cargo Delivery'), findsOneWidget);
    expect(find.text('456 Express Way'), findsOneWidget);
    expect(find.text('8:00 AM - 8:00 PM'), findsOneWidget);
    expect(find.text('30.0'), findsOneWidget);
    expect(find.text('15.0'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pump();
    expect(find.text('https://example.com/logo.png'), findsAtLeastNWidgets(1));
  });

  testWidgets('Navigates to OwnerConfigurationScreen from SettingsScreen',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(createOwnerConfigApp(homeScreen: const SettingsScreen()));
    await tester.pumpAndSettle();

    final rowFinder = find.byKey(const Key('owner_config_setting_row'));
    expect(rowFinder, findsOneWidget);

    await tester.ensureVisible(rowFinder);
    await tester.tap(rowFinder);
    await tester.pumpAndSettle();

    expect(find.byType(OwnerConfigurationScreen), findsOneWidget);
    expect(find.text('Business Details'), findsOneWidget);
  });

  testWidgets('Displays validation error when business name is empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerConfigApp());
    await tester.pumpAndSettle();

    final nameField = find.byKey(const Key('owner_config_name_field'));
    await tester.enterText(nameField, '');

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Business name is required.'), findsOneWidget);
  });

  testWidgets('Displays validation error when coverage radius is invalid',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerConfigApp());
    await tester.pumpAndSettle();

    final nameField = find.byKey(const Key('owner_config_name_field'));
    await tester.enterText(nameField, 'Valid Business');

    final basePriceField =
        find.byKey(const Key('owner_config_base_price_field'));
    await tester.enterText(basePriceField, '10.00');

    final pricePerKmField =
        find.byKey(const Key('owner_config_price_per_km_field'));
    await tester.enterText(pricePerKmField, '1.50');

    final radiusField = find.byKey(const Key('owner_config_radius_field'));
    await tester.enterText(radiusField, '-5');

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid radius > 0.'), findsOneWidget);
  });

  testWidgets('Submits form successfully and displays confirmation SnackBar',
      (WidgetTester tester) async {
    final existingService = [
      {
        'id': 'svc-777',
        'tenant_id': 'owner-config-1',
        'name': 'Existing Business',
        'category': 'delivery',
        'coverage_radius_km': 20.0,
        'tenant_base_price': 10.0,
        'tenant_price_per_km': 1.0,
      }
    ];

    await tester.pumpWidget(createOwnerConfigApp(services: existingService));
    await tester.pumpAndSettle();

    final nameField = find.byKey(const Key('owner_config_name_field'));
    await tester.enterText(nameField, 'Updated Express Fleet');

    final radiusField = find.byKey(const Key('owner_config_radius_field'));
    await tester.enterText(radiusField, '40.0');

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
        find.text('Owner configuration updated successfully'), findsOneWidget);
  });

  testWidgets('Displays error banner when API update fails',
      (WidgetTester tester) async {
    final existingService = [
      {
        'id': 'svc-777',
        'tenant_id': 'owner-config-1',
        'name': 'Existing Business',
        'category': 'delivery',
        'coverage_radius_km': 20.0,
        'tenant_base_price': 10.0,
        'tenant_price_per_km': 1.0,
      }
    ];

    await tester.pumpWidget(createOwnerConfigApp(
      services: existingService,
      shouldFailUpdate: true,
    ));
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner_config_error_banner')), findsOneWidget);
    expect(find.text(ErrorMessages.badRequest), findsOneWidget);
  });

  testWidgets(
      'Tapping image pick button invokes picker and updates photo URL field',
      (WidgetTester tester) async {
    bool pickerInvoked = false;
    await tester.pumpWidget(createOwnerConfigApp(
      homeScreen: OwnerConfigurationScreen(
        onPickImage: (context) async {
          pickerInvoked = true;
          return 'https://example.com/uploaded_logo.png';
        },
      ),
    ));
    await tester.pumpAndSettle();

    final pickBtn = find.byKey(const Key('owner_config_pick_image_button'));
    expect(pickBtn, findsOneWidget);

    await tester.ensureVisible(pickBtn);
    await tester.tap(pickBtn);
    await tester.pumpAndSettle();

    expect(pickerInvoked, isTrue);
    expect(find.text('https://example.com/uploaded_logo.png'), findsOneWidget);
  });
}
