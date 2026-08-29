import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/component_library_screen.dart';
import 'package:frontend/screens/customer_home_screen.dart';
import 'package:frontend/screens/customer_job_map_screen.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/employee_history_screen.dart';
import 'package:frontend/screens/employee_home_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/employee_screen.dart';
import 'package:frontend/screens/forgot_password_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/screens/kyc_document_upload_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/my_account_screen.dart';
import 'package:frontend/screens/notifications_screen.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/screens/owner_configuration_screen.dart';
import 'package:frontend/screens/owner_fleet_map_screen.dart';
import 'package:frontend/screens/owner_history_screen.dart';
import 'package:frontend/screens/owner_reconciliation_queue_screen.dart';
import 'package:frontend/screens/rating_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/signup_screen.dart';
import 'package:frontend/screens/subscription_screen.dart';
import 'package:frontend/screens/update_required_screen.dart';
import 'package:frontend/screens/wallet_screen.dart';

// Golden snapshot regression tests for migrated screens (P6).
//
// Regenerate snapshots after intentional visual changes with:
//   flutter test --update-goldens test/golden_screens_test.dart
//
// Fonts: in the test environment Google Fonts HTTP fetching fails and the
// deterministic test font (Ahem) is used instead of live-downloaded Poppins.
// Golden diffs therefore surface layout/token/template changes, not font
// raster differences.

const _mobile = Size(360, 800);
const _tablet = Size(768, 1024);
const _desktop = Size(1280, 800);

class _MockAuthProvider extends AuthProvider {
  final UserProfile? mockUser;
  @override
  String? get token => 'golden-test-token';

  _MockAuthProvider(super.apiClient, {this.mockUser});

  @override
  UserProfile? get user => mockUser;

  @override
  Future<void> fetchUserProfile() async {}
}

class _MockNotificationsProvider extends NotificationsProvider {
  final List<NotificationModel> mockList;
  _MockNotificationsProvider(super.apiClient, this.mockList);

  @override
  List<NotificationModel> get notifications => mockList;

  @override
  bool get isConnected => true;
}

class _MockReconciliationProvider extends ReconciliationProvider {
  final List<ReconciliationJob> initialJobs;
  _MockReconciliationProvider(super.apiClient, this.initialJobs) {
    _testQueue = List.from(initialJobs);
    _testError = null;
  }

  late List<ReconciliationJob> _testQueue;
  String? _testError;

  @override
  List<ReconciliationJob> get queue => List.unmodifiable(_testQueue);
  @override
  String? get error => _testError;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchQueue() async {}
}

class _MockMarketplaceProvider extends MarketplaceProvider {
  final List<Job> jobs;
  final List<MarketplaceService> mockServices;
  _MockMarketplaceProvider(super.apiClient, this.jobs,
      {this.mockServices = const []});

  @override
  List<Job> get customerJobs => jobs;
  @override
  List<MarketplaceService> get services => mockServices;
  @override
  String? get error => null;
  @override
  bool get isLoading => false;

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async => jobs;

  @override
  Future<Job?> fetchJobStatus(String jobId, String token) async {
    return jobs.firstWhere((j) => j.id == jobId, orElse: () => jobs.first);
  }

  @override
  Future<Map<String, dynamic>> fetchRatings(String token) async {
    return {'ratings': []};
  }
}

class _MockChatProvider extends ChatProvider {
  final List<ChatMessage> mockMessages;
  _MockChatProvider(super.apiClient, {this.mockMessages = const []});

  @override
  List<ChatMessage> get messages => mockMessages;
  @override
  bool get isConnected => true;
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchHistory(String jobId, String token) async {}
  @override
  void connectAndSubscribe(String jobId, String token) {}
  @override
  void disconnect() {}
}

class _MockMapTrackingProvider extends MapTrackingProvider {
  _MockMapTrackingProvider(super.apiClient);

  @override
  bool get isConnected => true;
  @override
  bool get isLoading => false;
  @override
  void connectAndSubscribe(String channel, String token,
      {WebSocketChannel? customChannel}) {}
  @override
  void disconnect() {}
}

class _MockOwnerProvider extends OwnerProvider {
  final List<Job> mockJobs;
  final List<Map<String, dynamic>> mockServices;
  final List<Map<String, dynamic>> mockEmployees;
  final List<PayoutRequest> mockPayouts;

  _MockOwnerProvider(
    super.apiClient, {
    this.mockJobs = const [],
    this.mockServices = const [],
    this.mockEmployees = const [],
    this.mockPayouts = const [],
  });

  @override
  double get walletBalance => 1500.0;
  @override
  double get escrowBalance => 400.0;
  @override
  double get withdrawableBalance => 1100.0;
  @override
  String get subscriptionTier => 'paid';
  @override
  List<dynamic> get ledgerEntries => const [];
  @override
  List<Job> get ownerJobs => mockJobs;
  @override
  double? get platformFeePercentage => 10.0;
  @override
  List<dynamic> get employees => mockEmployees;
  @override
  List<PayoutRequest> get payoutRequests => mockPayouts;
  @override
  List<Map<String, dynamic>> get services => mockServices;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;

  @override
  Future<void> fetchDashboardData(String tenantId) async {}
  @override
  Future<void> fetchPlatformConfig() async {}
  @override
  Future<List<PayoutRequest>> fetchPayoutRequests() async => mockPayouts;
  @override
  Future<void> fetchServices() async {}
  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async =>
      mockEmployees;
  @override
  Future<void> fetchOwnerJobs(String token) async {}
  @override
  Future<void> fetchAuditLog({
    required String tenantId,
    required String requesterToken,
  }) async {}
}

UserProfile _owner() => UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'Owner One',
      role: 'owner',
      kycStatus: 'approved',
    );

UserProfile _employee() => UserProfile(
      id: 'emp-1',
      email: 'employee@example.com',
      username: 'Employee One',
      role: 'employee',
      kycStatus: 'approved',
    );

class _MockEmployeeJobsProvider extends EmployeeJobsProvider {
  final List<Job> mockJobs;
  _MockEmployeeJobsProvider(super.apiClient, {this.mockJobs = const []});

  @override
  List<Job> get jobs => mockJobs;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

class _MockEmployeeLocationProvider extends EmployeeLocationProvider {
  _MockEmployeeLocationProvider(super.apiClient);

  @override
  LocationSharingStatus get status => LocationSharingStatus.tracking;
  @override
  bool get isTracking => true;
  @override
  String? get error => null;
  @override
  Future<void> startTracking(String jobId, String userToken) async {}
  @override
  Future<void> stopTracking({bool notify = true}) async {}
}

UserProfile _customer() => UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'Customer One',
      role: 'user',
    );

Job _job(String id, String status) => Job(
      id: id,
      ownerId: 'owner-1',
      userId: 'cust-1',
      serviceId: 'service-delivery-1',
      status: status,
      location: JobLocation(latitude: 30.0444, longitude: 31.2357),
      paymentMethod: 'cod',
    );

NotificationModel _notification(
  String id,
  String title,
  DateTime ts, {
  bool isRead = false,
}) =>
    NotificationModel(
      id: id,
      type: 'job_update',
      tenantId: 'tenant-1',
      title: title,
      body: 'Your delivery is progressing as expected.',
      timestamp: ts,
      isRead: isRead,
    );

Future<void> _pumpGolden(
  WidgetTester tester,
  Widget app,
  Size viewport,
  String name,
) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app);
  // Flush bundled google_fonts asset loads outside the fake async zone so
  // glyph rendering is fully settled (and identical) before rasterization.
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

MaterialApp _localizedApp(
    {required Widget home, Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: quickDeliveryTheme,
    darkTheme: quickDeliveryDarkTheme,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  );
}

Widget _authApp({
  required Widget home,
  Brightness brightness = Brightness.light,
  UserProfile? user,
}) {
  final api = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(
        value: _MockAuthProvider(api, mockUser: user ?? _customer()),
      ),
    ],
    child: _localizedApp(
      brightness: brightness,
      home: home,
    ),
  );
}

Widget _customerApp({
  required Widget home,
  Brightness brightness = Brightness.light,
  List<Job>? jobs,
  List<MarketplaceService>? services,
}) {
  final api = ApiClient();
  final sampleJobs = jobs ??
      [
        _job('custjob1234', 'active'),
        _job('custjob5678', 'completed'),
      ];
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(
        value: _MockAuthProvider(api, mockUser: _customer()),
      ),
      ChangeNotifierProvider<MarketplaceProvider>.value(
        value: _MockMarketplaceProvider(api, sampleJobs,
            mockServices: services ??
                [
                  MarketplaceService(
                    id: 'srv-1',
                    tenantId: 'tenant-1',
                    name: 'Express Cargo',
                    category: 'delivery',
                    basePrice: 45.0,
                    tenantBasePrice: 45.0,
                    tenantPricePerKM: 2.5,
                    latitude: 30.0444,
                    longitude: 31.2357,
                    distanceKM: 3.2,
                    finalPrice: 53.0,
                  ),
                ]),
      ),
      ChangeNotifierProvider<NotificationsProvider>.value(
        value: _MockNotificationsProvider(api, []),
      ),
      ChangeNotifierProvider<MapTrackingProvider>.value(
        value: _MockMapTrackingProvider(api),
      ),
      ChangeNotifierProvider<ChatProvider>.value(
        value: _MockChatProvider(api, mockMessages: [
          ChatMessage(
            channel: 'job:custjob1234',
            senderId: 'driver-1',
            senderUsername: 'Ahmed Driver',
            content: 'I am on my way to pick up the package.',
            type: 'message',
          ),
        ]),
      ),
    ],
    child: _localizedApp(
      brightness: brightness,
      home: home,
    ),
  );
}

Widget _ownerApp({
  required Widget home,
  Brightness brightness = Brightness.light,
  List<Job>? jobs,
  List<Map<String, dynamic>>? services,
  List<Map<String, dynamic>>? employees,
}) {
  final api = ApiClient();
  final sampleJobs = jobs ??
      [
        _job('ownerjob1234', 'active'),
        _job('ownerjob5678', 'completed'),
      ];
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(
        value: _MockAuthProvider(api, mockUser: _owner()),
      ),
      ChangeNotifierProvider<OwnerProvider>.value(
        value: _MockOwnerProvider(
          api,
          mockJobs: sampleJobs,
          mockServices: services ??
              [
                {
                  'id': 'srv-owner-1',
                  'tenant_id': 'owner-1',
                  'name': 'Standard Truck Delivery',
                  'category': 'delivery',
                  'base_price': 120.0,
                  'is_active': true,
                },
              ],
          mockEmployees: employees ??
              [
                {
                  'id': 'emp-1',
                  'username': 'Tamer Driver',
                  'email': 'tamer@example.com',
                  'status': 'active',
                },
              ],
          mockPayouts: [
            PayoutRequest(
              id: 'payout-1',
              tenantId: 'owner-1',
              amount: 500.0,
              status: 'paid',
              payoutMethod: 'instapay',
              accountDetails: '01012345678',
              createdAt: DateTime(2026, 8, 20, 10, 0),
              updatedAt: DateTime(2026, 8, 20, 12, 0),
            ),
          ],
        ),
      ),
      ChangeNotifierProvider<NotificationsProvider>.value(
        value: _MockNotificationsProvider(api, []),
      ),
      ChangeNotifierProvider<MarketplaceProvider>.value(
        value: _MockMarketplaceProvider(api, sampleJobs),
      ),
      ChangeNotifierProvider<MapTrackingProvider>.value(
        value: _MockMapTrackingProvider(api),
      ),
    ],
    child: _localizedApp(
      brightness: brightness,
      home: home,
    ),
  );
}

Widget _employeeApp({
  required Widget home,
  Brightness brightness = Brightness.light,
  UserProfile? user,
  List<Job>? jobs,
}) {
  final api = ApiClient();
  final sampleJobs = jobs ??
      [
        _job('empjob1234', 'assigned'),
        _job('empjob5678', 'completed'),
      ];
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(
        value: _MockAuthProvider(api, mockUser: user ?? _employee()),
      ),
      ChangeNotifierProvider<EmployeeJobsProvider>.value(
        value: _MockEmployeeJobsProvider(api, mockJobs: sampleJobs),
      ),
      ChangeNotifierProvider<EmployeeLocationProvider>.value(
        value: _MockEmployeeLocationProvider(api),
      ),
      ChangeNotifierProvider<OwnerProvider>.value(
        value: _MockOwnerProvider(api),
      ),
      ChangeNotifierProvider<NotificationsProvider>.value(
        value: _MockNotificationsProvider(api, []),
      ),
      ChangeNotifierProvider<MarketplaceProvider>.value(
        value: _MockMarketplaceProvider(api, sampleJobs),
      ),
      ChangeNotifierProvider<MapTrackingProvider>.value(
        value: _MockMapTrackingProvider(api),
      ),
    ],
    child: _localizedApp(
      brightness: brightness,
      home: home,
    ),
  );
}

void main() {
  setUpAll(() async {
    // Poppins is bundled as an asset (assets/fonts/) — never fetch at runtime.
    GoogleFonts.config.allowRuntimeFetching = false;
    // Deterministic font preload (golden environment contract): load the five
    // bundled Poppins TTFs directly into the engine so glyph rasterization
    // depends only on the pinned Flutter build, not on google_fonts' async
    // asset-loading path or host-system fonts. Scoped to this suite because
    // global binding initialization in flutter_test_config.dart breaks other
    // suites that construct HTTP clients outside test zones.
    TestWidgetsFlutterBinding.ensureInitialized();
    const fontPaths = <String>[
      'assets/fonts/Poppins-Regular.ttf',
      'assets/fonts/Poppins-Medium.ttf',
      'assets/fonts/Poppins-SemiBold.ttf',
      'assets/fonts/Poppins-Bold.ttf',
      'assets/fonts/Poppins-ExtraBold.ttf',
    ];
    final loader = FontLoader('Poppins');
    for (final path in fontPaths) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  });

  testWidgets('GOLDEN component library — mobile', (tester) async {
    await _pumpGolden(
      tester,
      _localizedApp(home: const ComponentLibraryScreen()),
      _mobile,
      'component_library_mobile_360x800',
    );
  });

  testWidgets('GOLDEN component library — tablet', (tester) async {
    await _pumpGolden(
      tester,
      _localizedApp(home: const ComponentLibraryScreen()),
      _tablet,
      'component_library_tablet_768x1024',
    );
  });

  testWidgets('GOLDEN component library — desktop web', (tester) async {
    await _pumpGolden(
      tester,
      _localizedApp(home: const ComponentLibraryScreen()),
      _desktop,
      'component_library_desktop_1280x800',
    );
  });

  testWidgets('GOLDEN notifications screen (P0 migration)', (tester) async {
    final api = ApiClient();
    final now = DateTime(2026, 8, 21, 12, 0);
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value: _MockAuthProvider(api),
        ),
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: _MockNotificationsProvider(api, [
            _notification('n1', 'Order picked up',
                now.subtract(const Duration(hours: 1))),
            _notification('n2', 'Courier assigned',
                now.subtract(const Duration(hours: 3))),
            _notification('n3', 'Payment confirmed',
                now.subtract(const Duration(days: 1)),
                isRead: true),
          ]),
        ),
      ],
      child: _localizedApp(
        home: NotificationsScreen(clock: () => now, showBackButton: true),
      ),
    );
    await _pumpGolden(
        tester, app, _mobile, 'notifications_screen_mobile_360x800');
    await _pumpGolden(
        tester, app, _tablet, 'notifications_screen_tablet_768x1024');
    await _pumpGolden(
        tester, app, _desktop, 'notifications_screen_desktop_1280x800');
  });

  testWidgets('GOLDEN owner reconciliation queue screen (P0 migration)',
      (tester) async {
    final api = ApiClient();
    final app = ChangeNotifierProvider<ReconciliationProvider>.value(
      value: _MockReconciliationProvider(api, [
        ReconciliationJob(
          id: 'job-golden-101',
          ownerId: 'owner-1',
          serviceId: 'service-shipping-1',
          userId: 'customer-1',
          employeeId: 'employee-1',
          status: 'escrow_reconciliation_required',
          location: JobLocation(latitude: 30.0444, longitude: 31.2357),
          paymentMethod: 'escrow',
          lockedEscrowAmount: 50.0,
          reconciliationNote: 'actual 2.00 km vs booked 10.00 km',
          escrowFailureReason: 'under_distance_mismatch',
          createdAt: DateTime(2026, 8, 20, 9, 30),
          updatedAt: DateTime(2026, 8, 20, 10, 0),
        ),
      ]),
      child: _localizedApp(
          home: const OwnerReconciliationQueueScreen(showBackButton: true)),
    );
    await _pumpGolden(
        tester, app, _mobile, 'reconciliation_queue_mobile_360x800');
    await _pumpGolden(
        tester, app, _tablet, 'reconciliation_queue_tablet_768x1024');
    await _pumpGolden(
        tester, app, _desktop, 'reconciliation_queue_desktop_1280x800');
  });

  testWidgets('GOLDEN customer jobs screen — list template (P2 migration)',
      (tester) async {
    final api = ApiClient();
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value: _MockAuthProvider(api, mockUser: _customer()),
        ),
        ChangeNotifierProvider<MarketplaceProvider>.value(
          value: _MockMarketplaceProvider(api, [
            _job('abcd1234abcd1234', 'active'),
            _job('efgh5678efgh5678', 'completed'),
            _job('ijkl9012ijkl9012', 'cancelled'),
          ]),
        ),
      ],
      child: _localizedApp(home: const CustomerJobsScreen()),
    );
    await _pumpGolden(tester, app, _mobile, 'customer_jobs_mobile_360x800');
  });

  testWidgets('GOLDEN login screen — form template (P2 migration)',
      (tester) async {
    final api = ApiClient();
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(
          value: _MockAuthProvider(api, mockUser: _customer()),
        ),
      ],
      child: _localizedApp(home: const LoginScreen()),
    );
    await _pumpGolden(tester, app, _mobile, 'login_screen_mobile_360x800');
    await _pumpGolden(tester, app, _tablet, 'login_screen_tablet_768x1024');
  });

  // ── A8 visual-fix pass: DARK MODE evidence set (mobile viewport) ──
  testWidgets('GOLDEN dark component library — mobile', (tester) async {
    await _pumpGolden(
      tester,
      _localizedApp(
          brightness: Brightness.dark, home: const ComponentLibraryScreen()),
      _mobile,
      'component_library_dark_mobile_360x800',
    );
  });

  testWidgets('GOLDEN dark login screen — mobile', (tester) async {
    final api = ApiClient();
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(
          value: _MockAuthProvider(api, mockUser: _customer()),
        ),
      ],
      child: _localizedApp(
        brightness: Brightness.dark,
        home: const LoginScreen(),
      ),
    );
    await _pumpGolden(tester, app, _mobile, 'login_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN dark notifications screen — mobile', (tester) async {
    final api = ApiClient();
    final now = DateTime(2026, 8, 21, 12, 0);
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _MockAuthProvider(api)),
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: _MockNotificationsProvider(api, [
            _notification('n1', 'Order picked up',
                now.subtract(const Duration(hours: 1))),
            _notification('n2', 'Courier assigned',
                now.subtract(const Duration(hours: 3))),
          ]),
        ),
      ],
      child: _localizedApp(
        brightness: Brightness.dark,
        home: NotificationsScreen(clock: () => now, showBackButton: true),
      ),
    );
    await _pumpGolden(
        tester, app, _mobile, 'notifications_dark_mobile_360x800');
  });

  testWidgets('GOLDEN dark customer jobs screen — mobile', (tester) async {
    final api = ApiClient();
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _MockAuthProvider(api)),
        ChangeNotifierProvider<MarketplaceProvider>.value(
          value: _MockMarketplaceProvider(api, [
            _job('abcd1234abcd1234', 'active'),
            _job('efgh5678efgh5678', 'completed'),
            _job('ijkl9012ijkl9012', 'cancelled'),
          ]),
        ),
      ],
      child: _localizedApp(
        brightness: Brightness.dark,
        home: const CustomerJobsScreen(),
      ),
    );
    await _pumpGolden(
        tester, app, _mobile, 'customer_jobs_dark_mobile_360x800');
  });

  testWidgets('GOLDEN dark reconciliation queue — mobile', (tester) async {
    final api = ApiClient();
    final app = MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
            value: _MockAuthProvider(api)),
        ChangeNotifierProvider<ReconciliationProvider>.value(
          value: _MockReconciliationProvider(api, [
            ReconciliationJob(
              id: 'job-golden-101',
              ownerId: 'owner-1',
              serviceId: 'service-shipping-1',
              userId: 'customer-1',
              employeeId: 'employee-1',
              status: 'escrow_reconciliation_required',
              location: JobLocation(latitude: 30.0444, longitude: 31.2357),
              paymentMethod: 'escrow',
              lockedEscrowAmount: 50.0,
              reconciliationNote: 'actual 2.00 km vs booked 10.00 km',
              escrowFailureReason: 'under_distance_mismatch',
              createdAt: DateTime(2026, 8, 20, 9, 30),
              updatedAt: DateTime(2026, 8, 20, 10, 0),
            ),
          ]),
        ),
      ],
      child: _localizedApp(
        brightness: Brightness.dark,
        home: const OwnerReconciliationQueueScreen(showBackButton: true),
      ),
    );
    await _pumpGolden(
        tester, app, _mobile, 'reconciliation_queue_dark_mobile_360x800');
  });

  // ── BATCH 1: Auth & Common / Global Screens ──
  testWidgets('GOLDEN signup screen — mobile', (tester) async {
    final app = _authApp(home: const SignupScreen());
    await _pumpGolden(tester, app, _mobile, 'signup_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark signup screen — mobile', (tester) async {
    final app =
        _authApp(home: const SignupScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'signup_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN otp screen — mobile', (tester) async {
    final app = _authApp(
      home: const OtpScreen(email: 'customer@example.com', devOtp: '123456'),
    );
    await _pumpGolden(tester, app, _mobile, 'otp_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark otp screen — mobile', (tester) async {
    final app = _authApp(
      home: const OtpScreen(email: 'customer@example.com', devOtp: '123456'),
      brightness: Brightness.dark,
    );
    await _pumpGolden(tester, app, _mobile, 'otp_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN forgot password screen — mobile', (tester) async {
    final app = _authApp(home: const ForgotPasswordScreen());
    await _pumpGolden(tester, app, _mobile, 'forgot_password_mobile_360x800');
  });

  testWidgets('GOLDEN dark forgot password screen — mobile', (tester) async {
    final app = _authApp(
      home: const ForgotPasswordScreen(),
      brightness: Brightness.dark,
    );
    await _pumpGolden(
        tester, app, _mobile, 'forgot_password_dark_mobile_360x800');
  });

  testWidgets('GOLDEN update required screen — mobile', (tester) async {
    final app = _authApp(
      home: const UpdateRequiredScreen(
        minimumVersion: '2.0.0',
        downloadUrl:
            'https://play.google.com/store/apps/details?id=com.quickdelivery',
      ),
    );
    await _pumpGolden(tester, app, _mobile, 'update_required_mobile_360x800');
  });

  testWidgets('GOLDEN dark update required screen — mobile', (tester) async {
    final app = _authApp(
      home: const UpdateRequiredScreen(
        minimumVersion: '2.0.0',
        downloadUrl:
            'https://play.google.com/store/apps/details?id=com.quickdelivery',
      ),
      brightness: Brightness.dark,
    );
    await _pumpGolden(
        tester, app, _mobile, 'update_required_dark_mobile_360x800');
  });

  testWidgets('GOLDEN settings screen — mobile', (tester) async {
    final app = _authApp(home: const SettingsScreen());
    await _pumpGolden(tester, app, _mobile, 'settings_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark settings screen — mobile', (tester) async {
    final app = _authApp(
      home: const SettingsScreen(),
      brightness: Brightness.dark,
    );
    await _pumpGolden(
        tester, app, _mobile, 'settings_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN my account screen — mobile', (tester) async {
    final app = _authApp(home: const MyAccountScreen());
    await _pumpGolden(tester, app, _mobile, 'my_account_mobile_360x800');
  });

  testWidgets('GOLDEN dark my account screen — mobile', (tester) async {
    final app = _authApp(
      home: const MyAccountScreen(),
      brightness: Brightness.dark,
    );
    await _pumpGolden(tester, app, _mobile, 'my_account_dark_mobile_360x800');
  });

  // ── BATCH 2: Customer Screens ──
  testWidgets('GOLDEN customer home screen — mobile', (tester) async {
    final app = _customerApp(home: const CustomerHomeScreen());
    await _pumpGolden(tester, app, _mobile, 'customer_home_mobile_360x800');
  });

  testWidgets('GOLDEN dark customer home screen — mobile', (tester) async {
    final app = _customerApp(
        home: const CustomerHomeScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'customer_home_dark_mobile_360x800');
  });

  testWidgets('GOLDEN customer marketplace screen — mobile', (tester) async {
    final app = _customerApp(home: const CustomerMarketplaceScreen());
    await _pumpGolden(
        tester, app, _mobile, 'customer_marketplace_mobile_360x800');
  });

  testWidgets('GOLDEN dark customer marketplace screen — mobile',
      (tester) async {
    final app = _customerApp(
        home: const CustomerMarketplaceScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'customer_marketplace_dark_mobile_360x800');
  });

  testWidgets('GOLDEN customer job map screen — mobile', (tester) async {
    final app = _customerApp(
      home: const CustomerJobMapScreen(
        jobId: 'custjob1234',
        token: 'golden-token',
      ),
    );
    await _pumpGolden(tester, app, _mobile, 'customer_job_map_mobile_360x800');
  });

  testWidgets('GOLDEN dark customer job map screen — mobile', (tester) async {
    final app = _customerApp(
      home: const CustomerJobMapScreen(
        jobId: 'custjob1234',
        token: 'golden-token',
      ),
      brightness: Brightness.dark,
    );
    await _pumpGolden(
        tester, app, _mobile, 'customer_job_map_dark_mobile_360x800');
  });

  testWidgets('GOLDEN job status screen — mobile', (tester) async {
    final app = _customerApp(
      home: JobStatusScreen(
        job: _job('custjob1234', 'active'),
        enablePolling: false,
      ),
    );
    await _pumpGolden(tester, app, _mobile, 'job_status_mobile_360x800');
  });

  testWidgets('GOLDEN dark job status screen — mobile', (tester) async {
    final app = _customerApp(
      home: JobStatusScreen(
        job: _job('custjob1234', 'active'),
        enablePolling: false,
      ),
      brightness: Brightness.dark,
    );
    await _pumpGolden(tester, app, _mobile, 'job_status_dark_mobile_360x800');
  });

  testWidgets('GOLDEN rating screen — mobile', (tester) async {
    final app = _customerApp(
      home: RatingScreen(job: _job('custjob1234', 'completed')),
    );
    await _pumpGolden(tester, app, _mobile, 'rating_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark rating screen — mobile', (tester) async {
    final app = _customerApp(
      home: RatingScreen(job: _job('custjob1234', 'completed')),
      brightness: Brightness.dark,
    );
    await _pumpGolden(
        tester, app, _mobile, 'rating_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN chat screen — mobile', (tester) async {
    final app = _customerApp(home: const ChatScreen(jobId: 'custjob1234'));
    await _pumpGolden(tester, app, _mobile, 'chat_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark chat screen — mobile', (tester) async {
    final app = _customerApp(
      home: const ChatScreen(jobId: 'custjob1234'),
      brightness: Brightness.dark,
    );
    await _pumpGolden(tester, app, _mobile, 'chat_screen_dark_mobile_360x800');
  });

  // ── BATCH 3: Owner Screens ──
  testWidgets('GOLDEN owner home screen — mobile', (tester) async {
    final app = _ownerApp(home: const HomeScreen());
    await _pumpGolden(tester, app, _mobile, 'owner_home_mobile_360x800');
  });

  testWidgets('GOLDEN dark owner home screen — mobile', (tester) async {
    final app =
        _ownerApp(home: const HomeScreen(), brightness: Brightness.dark);
    await _pumpGolden(tester, app, _mobile, 'owner_home_dark_mobile_360x800');
  });

  testWidgets('GOLDEN wallet screen — mobile', (tester) async {
    final app = _ownerApp(home: const WalletScreen());
    await _pumpGolden(tester, app, _mobile, 'wallet_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark wallet screen — mobile', (tester) async {
    final app =
        _ownerApp(home: const WalletScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'wallet_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN subscription screen — mobile', (tester) async {
    final app = _ownerApp(home: const SubscriptionScreen());
    await _pumpGolden(
        tester, app, _mobile, 'subscription_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark subscription screen — mobile', (tester) async {
    final app = _ownerApp(
        home: const SubscriptionScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'subscription_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN owner configuration screen — mobile', (tester) async {
    final app = _ownerApp(home: const OwnerConfigurationScreen());
    await _pumpGolden(
        tester, app, _mobile, 'owner_configuration_mobile_360x800');
  });

  testWidgets('GOLDEN dark owner configuration screen — mobile',
      (tester) async {
    final app = _ownerApp(
        home: const OwnerConfigurationScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'owner_configuration_dark_mobile_360x800');
  });

  testWidgets('GOLDEN owner fleet map screen — mobile', (tester) async {
    final app = _ownerApp(home: const OwnerFleetMapScreen(ownerId: 'owner-1'));
    await _pumpGolden(tester, app, _mobile, 'owner_fleet_map_mobile_360x800');
  });

  testWidgets('GOLDEN dark owner fleet map screen — mobile', (tester) async {
    final app = _ownerApp(
        home: const OwnerFleetMapScreen(ownerId: 'owner-1'),
        brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'owner_fleet_map_dark_mobile_360x800');
  });

  testWidgets('GOLDEN owner history screen — mobile', (tester) async {
    final app = _ownerApp(home: const OwnerHistoryScreen());
    await _pumpGolden(tester, app, _mobile, 'owner_history_mobile_360x800');
  });

  testWidgets('GOLDEN dark owner history screen — mobile', (tester) async {
    final app = _ownerApp(
        home: const OwnerHistoryScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'owner_history_dark_mobile_360x800');
  });

  // ── BATCH 4: Employee Screens & KYC ──
  testWidgets('GOLDEN employee home screen — mobile', (tester) async {
    final app = _employeeApp(home: const EmployeeHomeScreen());
    await _pumpGolden(tester, app, _mobile, 'employee_home_mobile_360x800');
  });

  testWidgets('GOLDEN dark employee home screen — mobile', (tester) async {
    final app = _employeeApp(
        home: const EmployeeHomeScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'employee_home_dark_mobile_360x800');
  });

  testWidgets('GOLDEN employee jobs screen — mobile', (tester) async {
    final app = _employeeApp(home: const EmployeeJobsScreen());
    await _pumpGolden(tester, app, _mobile, 'employee_jobs_mobile_360x800');
  });

  testWidgets('GOLDEN dark employee jobs screen — mobile', (tester) async {
    final app = _employeeApp(
        home: const EmployeeJobsScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'employee_jobs_dark_mobile_360x800');
  });

  testWidgets('GOLDEN employee screen — mobile', (tester) async {
    final app = _employeeApp(home: const EmployeeScreen());
    await _pumpGolden(tester, app, _mobile, 'employee_screen_mobile_360x800');
  });

  testWidgets('GOLDEN dark employee screen — mobile', (tester) async {
    final app =
        _employeeApp(home: const EmployeeScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'employee_screen_dark_mobile_360x800');
  });

  testWidgets('GOLDEN employee history screen — mobile', (tester) async {
    final app = _employeeApp(home: const EmployeeHistoryScreen());
    await _pumpGolden(tester, app, _mobile, 'employee_history_mobile_360x800');
  });

  testWidgets('GOLDEN dark employee history screen — mobile', (tester) async {
    final app = _employeeApp(
        home: const EmployeeHistoryScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'employee_history_dark_mobile_360x800');
  });

  testWidgets('GOLDEN kyc document upload screen — mobile', (tester) async {
    final app = _employeeApp(home: const KycDocumentUploadScreen());
    await _pumpGolden(
        tester, app, _mobile, 'kyc_document_upload_mobile_360x800');
  });

  testWidgets('GOLDEN dark kyc document upload screen — mobile',
      (tester) async {
    final app = _employeeApp(
        home: const KycDocumentUploadScreen(), brightness: Brightness.dark);
    await _pumpGolden(
        tester, app, _mobile, 'kyc_document_upload_dark_mobile_360x800');
  });
}
