import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/employee_home_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/employee_history_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/job.dart';

class MockAuthProviderForTest extends AuthProvider {
  MockAuthProviderForTest(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'employee-test-1',
        email: 'employee@example.com',
        username: 'test_worker',
        role: 'employee',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-employee-token';

  @override
  Future<bool> fetchUserProfile() async => true;
}

class MockEmployeeJobsProviderForTest extends EmployeeJobsProvider {
  final List<Job> mockJobs;

  MockEmployeeJobsProviderForTest(super.apiClient, {this.mockJobs = const []});

  @override
  List<Job> get jobs => mockJobs;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

class MockEmployeeLocationProviderForTest extends EmployeeLocationProvider {
  MockEmployeeLocationProviderForTest(super.apiClient);

  @override
  LocationSharingStatus get status => LocationSharingStatus.idle;
}

class MockNotificationsProviderForTest extends NotificationsProvider {
  MockNotificationsProviderForTest(super.apiClient);

  @override
  int get unreadCount => 0;
}

class MockThemeProviderForTest extends ThemeProvider {
  @override
  ThemeMode get themeMode => ThemeMode.light;
}

Widget createEmployeeHomeScreenApp({
  int initialTabIndex = 0,
  List<Job> mockJobs = const [],
}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => MockAuthProviderForTest(apiClient)),
      ChangeNotifierProvider<EmployeeJobsProvider>(
          create: (_) => MockEmployeeJobsProviderForTest(apiClient,
              mockJobs: mockJobs)),
      ChangeNotifierProvider<EmployeeLocationProvider>(
          create: (_) => MockEmployeeLocationProviderForTest(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => MockNotificationsProviderForTest(apiClient)),
      ChangeNotifierProvider<ThemeProvider>(
          create: (_) => MockThemeProviderForTest()),
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
      home: HomeScreen(initialTabIndex: initialTabIndex),
    ),
  );
}

void main() {
  final testActiveJob = Job(
    id: 'job-active-101',
    ownerId: 'owner-1',
    employeeId: 'employee-test-1',
    userId: 'customer-1',
    serviceId: 'service-1',
    status: 'active',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final testCompletedJob = Job(
    id: 'job-completed-202',
    ownerId: 'owner-1',
    employeeId: 'employee-test-1',
    userId: 'customer-2',
    serviceId: 'service-2',
    status: 'completed',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    updatedAt: DateTime.now(),
  );

  testWidgets('HomeScreen routes employee role to EmployeeHomeScreen tab shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeHomeScreen), findsOneWidget);
    expect(find.byKey(const Key('employee_bottom_navigation_bar')),
        findsOneWidget);
    expect(find.byKey(const Key('employee_nav_tab_home')), findsOneWidget);
    expect(find.byKey(const Key('employee_nav_tab_history')), findsOneWidget);
    expect(find.byKey(const Key('employee_nav_tab_settings')), findsOneWidget);

    final navBar = tester.widget<NavigationBar>(
        find.byKey(const Key('employee_bottom_navigation_bar')));
    expect(navBar.destinations.length, equals(3));
  });

  testWidgets('Tapping bottom nav tabs switches between Home, History, and Settings',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(
      initialTabIndex: 0,
      mockJobs: [testActiveJob, testCompletedJob],
    ));
    await tester.pumpAndSettle();

    // Tab 0: Home (Assigned Jobs)
    expect(find.byType(EmployeeJobsScreen), findsOneWidget);
    expect(find.textContaining('job-active-101'), findsOneWidget);
    expect(find.textContaining('job-completed-202'), findsNothing);

    // Tap History tab (index 1)
    await tester.tap(find.byKey(const Key('employee_nav_tab_history')));
    await tester.pumpAndSettle();
    expect(find.byType(EmployeeHistoryScreen), findsOneWidget);
    expect(find.textContaining('job-completed-202'), findsOneWidget);
    expect(find.textContaining('job-active-101'), findsNothing);

    // Tap Settings tab (index 2)
    await tester.tap(find.byKey(const Key('employee_nav_tab_settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('initialTabIndex 1 renders History tab directly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(
      initialTabIndex: 1,
      mockJobs: [testCompletedJob],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeHistoryScreen), findsOneWidget);
    expect(find.textContaining('job-completed-202'), findsOneWidget);
  });

  testWidgets('initialTabIndex 2 renders Settings tab directly',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(initialTabIndex: 2));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Demoted action simulator card is present below active jobs list',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(
      initialTabIndex: 0,
      mockJobs: [testActiveJob],
    ));
    await tester.pumpAndSettle();

    // Active job should be visible at top
    expect(find.textContaining('job-active-101'), findsOneWidget);

    // Simulator card should exist on Home tab below active jobs
    final simTitle = find.text('Employee Action Simulator');
    expect(simTitle, findsOneWidget);

    // Ensure scrolling to simulator card works cleanly
    await tester.ensureVisible(simTitle);
    await tester.pumpAndSettle();
    expect(simTitle, findsOneWidget);
  });

  testWidgets('Pull to refresh gesture on Home tab triggers refresh',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHomeScreenApp(initialTabIndex: 0));
    await tester.pumpAndSettle();

    await tester.fling(
        find.byType(RefreshIndicator), const Offset(0.0, 300.0), 1000.0);
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeHomeScreen), findsOneWidget);
  });
}
