import 'package:frontend/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/screens/owner_configuration_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/kyc_document_upload_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/user_profile.dart';

class MockAuthProviderForConfigTest extends AuthProvider {
  final String mockKycStatus;
  int fetchUserProfileCalls = 0;

  MockAuthProviderForConfigTest(
    super.apiClient, {
    this.mockKycStatus = 'approved',
  });

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-config-1',
        email: 'owner@example.com',
        username: 'config_owner',
        role: 'owner',
        kycStatus: mockKycStatus,
      );

  @override
  String? get token => 'mock-owner-token';

  @override
  Future<bool> fetchUserProfile() async {
    fetchUserProfileCalls++;
    return true;
  }
}

class MockOwnerProviderForConfigTest extends OwnerProvider {
  final List<dynamic> mockServices;
  final String? mockErrorMsg;
  final bool shouldFailUpdate;
  bool updateCalled = false;
  bool createCalled = false;
  Map<String, dynamic>? lastUpdatePayload;
  Map<String, dynamic>? lastCreatePayload;

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
  Future<Map<String, dynamic>> createService({
    required String name,
    required String category,
    required double tenantBasePrice,
    required double tenantPricePerKM,
    required double latitude,
    required double longitude,
    required String ownerId,
  }) async {
    createCalled = true;
    lastCreatePayload = {
      'name': name,
      'category': category,
      'tenant_base_price': tenantBasePrice,
      'tenant_price_per_km': tenantPricePerKM,
      'latitude': latitude,
      'longitude': longitude,
      'owner_id': ownerId,
    };
    if (shouldFailUpdate) {
      throw ApiClientException('Failed to create service', statusCode: 400);
    }
    return {'status': 'created', 'id': 'new-svc-123'};
  }

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
    double? latitude,
    double? longitude,
    String? scheduleMode,
    String? openTime,
    String? closeTime,
    List<Map<String, dynamic>>? perDaySchedule,
    String? timezone,
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
      'latitude': latitude,
      'longitude': longitude,
      'schedule_mode': scheduleMode,
      'open_time': openTime,
      'close_time': closeTime,
      'per_day_schedule': perDaySchedule,
      'timezone': timezone,
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
  String kycStatus = 'approved',
  MockAuthProviderForConfigTest? authProvider,
}) {
  final apiClient = ApiClient();
  final mockOwnerProvider = MockOwnerProviderForConfigTest(
    apiClient,
    mockServices: services,
    shouldFailUpdate: shouldFailUpdate,
  );
  final effectiveAuth = authProvider ??
      MockAuthProviderForConfigTest(apiClient, mockKycStatus: kycStatus);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: effectiveAuth),
      ChangeNotifierProvider<OwnerProvider>.value(value: mockOwnerProvider),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
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
      home: homeScreen ?? const OwnerConfigurationScreen(),
    ),
  );
}

({MockOwnerProviderForConfigTest mock, Widget app}) buildScheduleApp({
  required List<dynamic> services,
}) {
  final apiClient = ApiClient();
  final mock =
      MockOwnerProviderForConfigTest(apiClient, mockServices: services);
  final auth = MockAuthProviderForConfigTest(apiClient);
  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<OwnerProvider>.value(value: mock),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
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
      home: OwnerConfigurationScreen(),
    ),
  );
  return (mock: mock, app: app);
}

Map<String, dynamic> scheduleBaseService() => {
      'id': 'svc-sched-1',
      'tenant_id': 'owner-config-1',
      'name': 'Sched Shop',
      'category': 'delivery',
      'coverage_radius_km': 20.0,
      'tenant_base_price': 10.0,
      'tenant_price_per_km': 1.0,
      'latitude': 30.0444,
      'longitude': 31.2357,
    };

Future<void> pickTimeDialogOk(WidgetTester tester, Key buttonKey) async {
  final btn = find.byKey(buttonKey);
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsOneWidget);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  expect(find.byType(TimePickerDialog), findsNothing);
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

  testWidgets(
      'Opens LocationPickerMap dialog, confirms location, and submits selected coordinates',
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
        'latitude': 31.2000,
        'longitude': 29.9100,
      }
    ];

    await tester.pumpWidget(createOwnerConfigApp(services: existingService));
    await tester.pumpAndSettle();

    // Verify prepopulated coordinates are displayed
    expect(find.byKey(const Key('owner_config_location_text')), findsOneWidget);
    expect(find.textContaining('Lat: 31.2000'), findsOneWidget);

    // Open LocationPickerMap dialog
    final pickerBtn =
        find.byKey(const Key('owner_config_location_picker_button'));
    await tester.ensureVisible(pickerBtn);
    await tester.tap(pickerBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsOneWidget);

    // Confirm location dialog
    final confirmBtn = find.byKey(const Key('confirm_location_button'));
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_picker_dialog')), findsNothing);

    // Submit form
    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
        find.text('Owner configuration updated successfully'), findsOneWidget);
  });

  testWidgets(
      'KYC verification status badge remains visible on load and after save',
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
        'latitude': 30.0444,
        'longitude': 31.2357,
      }
    ];

    final mockAuth =
        MockAuthProviderForConfigTest(ApiClient(), mockKycStatus: 'approved');

    await tester.pumpWidget(createOwnerConfigApp(
      services: existingService,
      authProvider: mockAuth,
    ));
    await tester.pumpAndSettle();

    // 1. Initial Load: Verification badge must be present and show APPROVED
    final kycBadgeFinder =
        find.byKey(const Key('owner_config_kyc_status_badge'));
    expect(kycBadgeFinder, findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);

    // Banner should NOT be shown when KYC is approved
    expect(find.byKey(const Key('owner_config_kyc_banner')), findsNothing);

    // Initial load must have fetched user profile
    expect(mockAuth.fetchUserProfileCalls, greaterThanOrEqualTo(1));
    final initialFetchCount = mockAuth.fetchUserProfileCalls;

    // 2. Perform Save
    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // 3. Post-Save: Verification badge must remain visible and show APPROVED
    expect(kycBadgeFinder, findsOneWidget);
    expect(find.text('APPROVED'), findsOneWidget);

    // Form save must refresh user profile from authProvider
    expect(mockAuth.fetchUserProfileCalls, greaterThan(initialFetchCount));
  });

  testWidgets(
      'KYC pending status displays warning banner and pending badge, tapping navigates to upload screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerConfigApp(
      kycStatus: 'pending_super_admin_approval',
    ));
    await tester.pumpAndSettle();

    // 1. Verification badge must show PENDING APPROVAL
    expect(
        find.byKey(const Key('owner_config_kyc_status_badge')), findsOneWidget);
    expect(find.text('PENDING APPROVAL'), findsOneWidget);

    // 2. Warning banner must be present
    final bannerFinder = find.byKey(const Key('owner_config_kyc_banner'));
    expect(bannerFinder, findsOneWidget);
    expect(find.text('Identity Verification (KYC)'), findsOneWidget);

    // 3. Tapping banner must navigate to KycDocumentUploadScreen
    await tester.ensureVisible(bannerFinder);
    await tester.tap(bannerFinder);
    await tester.pumpAndSettle();

    expect(find.byType(KycDocumentUploadScreen), findsOneWidget);
  });

  testWidgets('KYC rejected status displays warning banner and rejected badge',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerConfigApp(
      kycStatus: 'rejected',
    ));
    await tester.pumpAndSettle();

    // 1. Verification badge must show REJECTED
    expect(
        find.byKey(const Key('owner_config_kyc_status_badge')), findsOneWidget);
    expect(find.text('REJECTED'), findsOneWidget);

    // 2. Warning banner must be present
    expect(find.byKey(const Key('owner_config_kyc_banner')), findsOneWidget);
  });

  testWidgets(
      'Schedule editor: same_daily sends open/close and omits per_day_schedule',
      (WidgetTester tester) async {
    final built = buildScheduleApp(services: [scheduleBaseService()]);
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    // Open the editor, accept the default 09:00 / 17:00 via dialog OK.
    await tester
        .ensureVisible(find.byKey(const Key('schedule_set_hours_button')));
    await tester.tap(find.byKey(const Key('schedule_set_hours_button')));
    await tester.pumpAndSettle();
    await pickTimeDialogOk(tester, const Key('schedule_open_time_button'));
    await pickTimeDialogOk(tester, const Key('schedule_close_time_button'));

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final payload = built.mock.lastUpdatePayload!;
    expect(payload['schedule_mode'], equals('same_daily'));
    expect(payload['open_time'], equals('09:00'));
    expect(payload['close_time'], equals('17:00'));
    expect(payload['per_day_schedule'], isNull);
    expect(payload['timezone'], isNull);
  });

  testWidgets('Schedule editor: per_day sends 7 well-formed entries',
      (WidgetTester tester) async {
    final built = buildScheduleApp(services: [scheduleBaseService()]);
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.byKey(const Key('schedule_set_hours_button')));
    await tester.tap(find.byKey(const Key('schedule_set_hours_button')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Different per day'));
    await tester.tap(find.text('Different per day'));
    await tester.pumpAndSettle();

    final wedSwitch = find.byKey(const Key('schedule_day_wed_off_switch'));
    await tester.ensureVisible(wedSwitch);
    await tester.tap(wedSwitch);
    await tester.pumpAndSettle();

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final payload = built.mock.lastUpdatePayload!;
    expect(payload['schedule_mode'], equals('per_day'));
    expect(payload['open_time'], isNull);
    expect(payload['close_time'], isNull);
    final perDay = payload['per_day_schedule'] as List;
    expect(perDay.length, equals(7));
    final days = perDay.map((e) => (e as Map)['day'] as String).toList();
    expect(days.toSet(),
        equals({'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'}));
    for (final e in perDay) {
      final m = e as Map;
      if (m['day'] == 'wed') {
        expect(m['is_off'], isTrue);
      } else {
        expect(m['is_off'], isFalse);
        expect(m['open_time'], equals('09:00'));
        expect(m['close_time'], equals('17:00'));
      }
    }
  });

  testWidgets(
      'Schedule editor: untouched editor sends none of the 5 schedule fields',
      (WidgetTester tester) async {
    final built = buildScheduleApp(services: [scheduleBaseService()]);
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    // Editor present but never opened.
    expect(find.byKey(const Key('schedule_set_hours_button')), findsOneWidget);

    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final payload = built.mock.lastUpdatePayload!;
    for (final k in [
      'schedule_mode',
      'open_time',
      'close_time',
      'per_day_schedule',
      'timezone'
    ]) {
      expect(payload[k], isNull, reason: 'field $k must be omitted');
    }
  });

  testWidgets(
      'Schedule editor: pre-populates stored hours without marking touched',
      (WidgetTester tester) async {
    final svc = scheduleBaseService();
    svc['schedule_mode'] = 'same_daily';
    svc['open_time'] = '08:00';
    svc['close_time'] = '20:00';
    final built = buildScheduleApp(services: [svc]);
    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    // Stored values render; set-hours button is gone (mode active).
    expect(find.text('Opens: 08:00'), findsOneWidget);
    expect(find.text('Closes: 20:00'), findsOneWidget);
    expect(find.byKey(const Key('schedule_set_hours_button')), findsNothing);

    // Submitting without touching sends nothing (loaded != intent).
    final saveButton = find.byKey(const Key('owner_config_save_button'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final payload = built.mock.lastUpdatePayload!;
    expect(payload['schedule_mode'], isNull);
    expect(payload['per_day_schedule'], isNull);
  });
}
