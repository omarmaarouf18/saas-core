import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/wallet_screen.dart';
import 'package:frontend/widgets/skeleton_loader.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile _user;

  MockAuthProviderForTest(super.apiClient, this._user);

  @override
  UserProfile? get user => _user;

  @override
  String? get token => 'mock-token-123';
}

class TestableMarketplaceProvider extends MarketplaceProvider {
  bool _loadingState = true;
  final List<MarketplaceService> _mockServices = [];

  TestableMarketplaceProvider(super.apiClient);

  @override
  bool get isLoading => _loadingState;

  @override
  List<MarketplaceService> get services => _mockServices;

  @override
  String? get error => null;

  void setLoading(bool value) {
    _loadingState = value;
    notifyListeners();
  }

  void setServices(List<MarketplaceService> servicesList) {
    _mockServices.clear();
    _mockServices.addAll(servicesList);
    notifyListeners();
  }

  @override
  Future<void> fetchServices({
    bool nearBy = true,
    double lat = 30.0444,
    double lon = 31.2357,
    double radius = 50.0,
    String sortBy = 'price',
  }) async {}

  @override
  Future<Map<String, dynamic>> fetchRatings(String token) async {
    return {'average_rating': 4.5, 'count': 10};
  }
}

class TestableOwnerProvider extends OwnerProvider {
  bool _loadingState = true;
  double _balance = 0.0;
  final List<Job> _jobs = [];

  TestableOwnerProvider(super.apiClient);

  @override
  bool get isLoading => _loadingState;

  @override
  double get walletBalance => _balance;

  @override
  List<Job> get ownerJobs => _jobs;

  @override
  List<dynamic> get ledgerEntries => [];

  void setLoading(bool value) {
    _loadingState = value;
    notifyListeners();
  }

  void setData({required double balance, List<Job>? jobs}) {
    _balance = balance;
    if (jobs != null) {
      _jobs.clear();
      _jobs.addAll(jobs);
    }
    notifyListeners();
  }

  @override
  Future<void> fetchDashboardData(String token) async {}

  @override
  Future<void> fetchOwnerJobs(String token) async {}

  @override
  Future<void> fetchPlatformConfig() async {}

  @override
  Future<List<PayoutRequest>> fetchPayoutRequests() async => [];
}

class TestableEmployeeJobsProvider extends EmployeeJobsProvider {
  bool _loadingState = true;
  final List<Job> _assignedJobs = [];

  TestableEmployeeJobsProvider(super.apiClient);

  @override
  bool get isLoading => _loadingState;

  @override
  List<Job> get jobs => _assignedJobs;

  @override
  String? get error => null;

  void setLoading(bool value) {
    _loadingState = value;
    notifyListeners();
  }

  void setJobs(List<Job> jobsList) {
    _assignedJobs.clear();
    _assignedJobs.addAll(jobsList);
    notifyListeners();
  }

  @override
  Future<void> fetchAssignedJobs(String token) async {}
}

class MockNotificationsProviderForTest extends NotificationsProvider {
  MockNotificationsProviderForTest(super.apiClient);

  @override
  int get unreadCount => 0;

  void connect(String token) {}
  void disconnect() {}
}

class MockEmployeeLocationProviderForTest extends EmployeeLocationProvider {
  MockEmployeeLocationProviderForTest(super.apiClient);

  @override
  bool get isTracking => false;
}

Widget buildTestableApp({
  required Widget child,
  required AuthProvider authProvider,
  required ThemeProvider themeProvider,
  required NotificationsProvider notificationsProvider,
  MarketplaceProvider? marketplaceProvider,
  OwnerProvider? ownerProvider,
  EmployeeJobsProvider? employeeJobsProvider,
  EmployeeLocationProvider? employeeLocationProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<NotificationsProvider>.value(
          value: notificationsProvider),
      if (marketplaceProvider != null)
        ChangeNotifierProvider<MarketplaceProvider>.value(
            value: marketplaceProvider),
      if (ownerProvider != null)
        ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
      if (employeeJobsProvider != null)
        ChangeNotifierProvider<EmployeeJobsProvider>.value(
            value: employeeJobsProvider),
      if (employeeLocationProvider != null)
        ChangeNotifierProvider<EmployeeLocationProvider>.value(
            value: employeeLocationProvider),
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
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  group('SkeletonLoader Primitives Unit Tests', () {
    testWidgets('SkeletonLoader renders with custom width and height',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonLoader(width: 100, height: 40),
          ),
        ),
      );

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('MarketplaceCardSkeleton renders shimmer layout',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarketplaceCardSkeleton(),
          ),
        ),
      );

      expect(find.byType(MarketplaceCardSkeleton), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsNWidgets(6));
    });

    testWidgets('HomeDashboardSkeleton renders metric & job card skeletons',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: HomeDashboardSkeleton()),
          ),
        ),
      );

      expect(find.byType(HomeDashboardSkeleton), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsWidgets);
    });

    testWidgets('EmployeeJobCardSkeleton renders card shimmer structure',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmployeeJobCardSkeleton(),
          ),
        ),
      );

      expect(find.byType(EmployeeJobCardSkeleton), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsNWidgets(6));
    });

    testWidgets('WalletScreenSkeleton renders wallet stats & tiles shimmer',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: WalletScreenSkeleton()),
          ),
        ),
      );

      expect(find.byType(WalletScreenSkeleton), findsOneWidget);
      expect(find.byType(SkeletonLoader), findsWidgets);
    });
  });

  group('Per-Screen Skeleton & Animated Cross-Fade Transition Tests', () {
    testWidgets(
        '1. CustomerMarketplaceScreen renders MarketplaceCardSkeleton on initial load and cross-fades on data arrival',
        (tester) async {
      final customerUser = UserProfile(
        id: 'cust-1',
        email: 'customer@example.com',
        username: 'cust_user',
        role: 'user',
      );
      final authProvider = MockAuthProviderForTest(apiClient, customerUser);
      final marketplaceProvider = TestableMarketplaceProvider(apiClient);
      final themeProvider = ThemeProvider();
      final notificationsProvider = MockNotificationsProviderForTest(apiClient);

      await tester.pumpWidget(buildTestableApp(
        child: const CustomerMarketplaceScreen(isEmbeddedInTab: true),
        authProvider: authProvider,
        themeProvider: themeProvider,
        notificationsProvider: notificationsProvider,
        marketplaceProvider: marketplaceProvider,
      ));

      // Initial state: isLoading is true -> skeleton card list is rendered
      expect(find.byKey(const ValueKey('marketplace_skeleton_list')),
          findsOneWidget);
      expect(find.byType(MarketplaceCardSkeleton), findsNWidgets(4));

      // Simulate data arrival
      marketplaceProvider.setServices([
        MarketplaceService(
          id: 'svc-1',
          tenantId: 'tenant-1',
          name: 'Fast Express Delivery',
          category: 'delivery',
          basePrice: 10.0,
          tenantBasePrice: 15.0,
          tenantPricePerKM: 2.0,
          latitude: 30.0444,
          longitude: 31.2357,
          distanceKM: 3.5,
          finalPrice: 22.0,
        ),
      ]);
      marketplaceProvider.setLoading(false);

      // Advance animation frame for AnimatedSwitcher transition
      await tester.pump();
      await tester.pump(AppMotion.durationMedium);
      await tester.pumpAndSettle();

      // Transition complete: skeleton gone, real service list displayed
      expect(find.byKey(const ValueKey('marketplace_skeleton_list')),
          findsNothing);
      expect(find.byKey(const ValueKey('marketplace_services_list')),
          findsOneWidget);
      expect(find.text('Fast Express Delivery'), findsOneWidget);
    });

    testWidgets(
        '2. HomeScreen renders HomeDashboardSkeleton on initial load and cross-fades to dashboard content',
        (tester) async {
      final ownerUser = UserProfile(
        id: 'owner-1',
        email: 'owner@example.com',
        username: 'owner_user',
        role: 'owner',
      );
      final authProvider = MockAuthProviderForTest(apiClient, ownerUser);
      final ownerProvider = TestableOwnerProvider(apiClient);
      final marketplaceProvider = TestableMarketplaceProvider(apiClient);
      final themeProvider = ThemeProvider();
      final notificationsProvider = MockNotificationsProviderForTest(apiClient);

      await tester.pumpWidget(buildTestableApp(
        child: const HomeScreen(initialTabIndex: 0),
        authProvider: authProvider,
        themeProvider: themeProvider,
        notificationsProvider: notificationsProvider,
        ownerProvider: ownerProvider,
        marketplaceProvider: marketplaceProvider,
      ));

      // Initial state: isLoading is true -> HomeDashboardSkeleton rendered
      expect(find.byKey(const ValueKey('home_dashboard_skeleton')),
          findsOneWidget);
      expect(find.byType(HomeDashboardSkeleton), findsOneWidget);

      // Data arrives
      ownerProvider.setData(balance: 150.0);
      ownerProvider.setLoading(false);

      await tester.pump();
      await tester.pump(AppMotion.durationMedium);
      await tester.pumpAndSettle();

      // Transition complete: skeleton gone, real content key active
      expect(
          find.byKey(const ValueKey('home_dashboard_skeleton')), findsNothing);
      expect(
          find.byKey(const ValueKey('home_dashboard_content')), findsOneWidget);
    });

    testWidgets(
        '3. EmployeeJobsScreen renders EmployeeJobCardSkeleton on initial load and cross-fades on jobs arrival',
        (tester) async {
      final empUser = UserProfile(
        id: 'emp-1',
        email: 'employee@example.com',
        username: 'emp_user',
        role: 'employee',
      );
      final authProvider = MockAuthProviderForTest(apiClient, empUser);
      final employeeJobsProvider = TestableEmployeeJobsProvider(apiClient);
      final employeeLocationProvider =
          MockEmployeeLocationProviderForTest(apiClient);
      final themeProvider = ThemeProvider();
      final notificationsProvider = MockNotificationsProviderForTest(apiClient);

      await tester.pumpWidget(buildTestableApp(
        child: const EmployeeJobsScreen(),
        authProvider: authProvider,
        themeProvider: themeProvider,
        notificationsProvider: notificationsProvider,
        employeeJobsProvider: employeeJobsProvider,
        employeeLocationProvider: employeeLocationProvider,
      ));

      // Initial state: isLoading true & jobs empty -> EmployeeJobCardSkeleton rendered
      expect(find.byKey(const ValueKey('employee_jobs_skeleton_list')),
          findsOneWidget);
      expect(find.byType(EmployeeJobCardSkeleton), findsNWidgets(3));

      // Jobs arrive
      employeeJobsProvider.setJobs([
        Job(
          id: 'job-101',
          ownerId: 'owner-1',
          userId: 'user-1',
          serviceId: 'svc-1',
          employeeId: 'emp-1',
          status: 'assigned',
          location: JobLocation(latitude: 30.0444, longitude: 31.2357),
          paymentMethod: 'cod',
        ),
      ]);
      employeeJobsProvider.setLoading(false);

      await tester.pump();
      await tester.pump(AppMotion.durationMedium);
      await tester.pumpAndSettle();

      // Skeleton gone, real content shown
      expect(find.byKey(const ValueKey('employee_jobs_skeleton_list')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('employee_jobs_content')), findsOneWidget);
    });

    testWidgets(
        '4. WalletScreen renders WalletScreenSkeleton on initial load and cross-fades to wallet content',
        (tester) async {
      final ownerUser = UserProfile(
        id: 'owner-1',
        email: 'owner@example.com',
        username: 'owner_user',
        role: 'owner',
      );
      final authProvider = MockAuthProviderForTest(apiClient, ownerUser);
      final ownerProvider = TestableOwnerProvider(apiClient);
      final themeProvider = ThemeProvider();
      final notificationsProvider = MockNotificationsProviderForTest(apiClient);

      await tester.pumpWidget(buildTestableApp(
        child: const WalletScreen(),
        authProvider: authProvider,
        themeProvider: themeProvider,
        notificationsProvider: notificationsProvider,
        ownerProvider: ownerProvider,
      ));

      // Initial state: isLoading true, balance 0 -> WalletScreenSkeleton rendered
      expect(
          find.byKey(const ValueKey('wallet_skeleton_loader')), findsOneWidget);
      expect(find.byType(WalletScreenSkeleton), findsOneWidget);

      // Data arrives
      ownerProvider.setData(balance: 300.00);
      ownerProvider.setLoading(false);

      await tester.pump();
      await tester.pump(AppMotion.durationMedium);
      await tester.pumpAndSettle();

      // Transition complete: skeleton gone, wallet content visible
      expect(
          find.byKey(const ValueKey('wallet_skeleton_loader')), findsNothing);
      expect(find.byKey(const ValueKey('wallet_content')), findsOneWidget);
      expect(find.text('My Wallet'), findsOneWidget);
    });
  });
}
