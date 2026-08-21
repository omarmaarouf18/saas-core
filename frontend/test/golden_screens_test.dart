import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/component_library_screen.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/notifications_screen.dart';
import 'package:frontend/screens/owner_reconciliation_queue_screen.dart';

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
  _MockMarketplaceProvider(super.apiClient, this.jobs);

  @override
  List<Job> get customerJobs => jobs;
  @override
  String? get error => null;
  @override
  bool get isLoading => false;
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

MaterialApp _localizedApp({required Widget home}) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  setUpAll(() {
    // Poppins is bundled as an asset (assets/fonts/) — never fetch at runtime.
    GoogleFonts.config.allowRuntimeFetching = false;
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
      child: _localizedApp(home: const NotificationsScreen()),
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
      child: _localizedApp(home: const OwnerReconciliationQueueScreen()),
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
}
