import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/screens/employee_history_screen.dart';
import 'package:frontend/widgets/status_badge.dart';

class MockAuthProviderForTest extends AuthProvider {
  MockAuthProviderForTest(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'emp-history-1',
        email: 'employee@example.com',
        username: 'worker_one',
        role: 'employee',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-token';

  @override
  Future<bool> fetchUserProfile() async => true;
}

class MockEmployeeJobsProviderForHistoryTest extends EmployeeJobsProvider {
  final List<Job> mockJobs;
  final bool mockIsLoading;
  final String? mockError;
  bool fetchAssignedJobsCalled = false;

  MockEmployeeJobsProviderForHistoryTest(
    super.apiClient, {
    this.mockJobs = const [],
    this.mockIsLoading = false,
    this.mockError,
  });

  @override
  List<Job> get jobs => mockJobs;

  @override
  bool get isLoading => mockIsLoading;

  @override
  String? get error => mockError;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {
    fetchAssignedJobsCalled = true;
  }
}

Widget createEmployeeHistoryScreenApp({
  bool isEmbeddedInTab = false,
  List<Job> jobs = const [],
  bool isLoading = false,
  String? error,
  MockEmployeeJobsProviderForHistoryTest? jobsProviderOverride,
}) {
  final apiClient = ApiClient();
  final provider = jobsProviderOverride ??
      MockEmployeeJobsProviderForHistoryTest(
        apiClient,
        mockJobs: jobs,
        mockIsLoading: isLoading,
        mockError: error,
      );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => MockAuthProviderForTest(apiClient),
      ),
      ChangeNotifierProvider<EmployeeJobsProvider>.value(
        value: provider,
      ),
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
      home: EmployeeHistoryScreen(isEmbeddedInTab: isEmbeddedInTab),
    ),
  );
}

void main() {
  final testCompletedJob = Job(
    id: 'job-completed-501',
    ownerId: 'owner-1',
    employeeId: 'emp-history-1',
    userId: 'cust-501',
    serviceId: 'service-delivery-1',
    status: 'completed',
    paymentMethod: 'cod',
    lockedEscrowAmount: 75.0,
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    updatedAt: DateTime.now(),
  );

  final testCancelledJob = Job(
    id: 'job-cancelled-502',
    ownerId: 'owner-1',
    employeeId: 'emp-history-1',
    userId: 'cust-502',
    serviceId: 'service-ride-1',
    status: 'cancelled',
    paymentMethod: 'wallet',
    cancellationReason: 'Customer vehicle issue',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    updatedAt: DateTime.now(),
  );

  final testActiveJob = Job(
    id: 'job-active-ignored',
    ownerId: 'owner-1',
    employeeId: 'emp-history-1',
    userId: 'cust-503',
    serviceId: 'service-shipping-1',
    status: 'active',
    paymentMethod: 'cod',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets(
      'Renders loading skeleton when jobs are loading and history is empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHistoryScreenApp(
      isEmbeddedInTab: true,
      isLoading: true,
      jobs: [],
    ));

    expect(find.byKey(const ValueKey('employee_history_skeleton_list')),
        findsOneWidget);
  });

  testWidgets(
      'Renders empty state when history has no completed or cancelled jobs',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHistoryScreenApp(
      isEmbeddedInTab: true,
      isLoading: false,
      jobs: [testActiveJob], // Active job should be ignored in history
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('employee_history_empty_state')), findsOneWidget);
    expect(find.text('No Completed Jobs Found'), findsOneWidget);
  });

  testWidgets(
      'Renders completed and cancelled jobs in history list with status badges and details',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHistoryScreenApp(
      isEmbeddedInTab: true,
      jobs: [testCompletedJob, testCancelledJob, testActiveJob],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('employee_history_list')), findsOneWidget);
    expect(find.byKey(Key('employee_history_card_${testCompletedJob.id}')),
        findsOneWidget);
    expect(find.byKey(Key('employee_history_card_${testCancelledJob.id}')),
        findsOneWidget);
    expect(find.byKey(Key('employee_history_card_${testActiveJob.id}')),
        findsNothing);

    // Verify job IDs and status badges
    expect(find.text('Job #job-completed-501'), findsOneWidget);
    expect(find.text('Job #job-cancelled-502'), findsOneWidget);
    expect(find.byType(StatusBadge), findsNWidgets(2));

    // Verify customer and payment chips
    expect(find.text('Customer: '), findsNWidgets(2));
    expect(find.text('cust-501'), findsOneWidget);
    expect(find.text('cust-502'), findsOneWidget);
    expect(find.text('Payment: '), findsNWidgets(2));
    expect(find.text('COD'), findsWidgets);
    expect(find.text('WALLET'), findsWidgets);

    // Verify escrow amount
    expect(find.text('75.00 Credits'), findsOneWidget);

    // Verify cancellation reason
    expect(find.text('Cancellation Reason: Customer vehicle issue'),
        findsOneWidget);
  });

  testWidgets('Renders error banner when provider has error and jobs are empty',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHistoryScreenApp(
      isEmbeddedInTab: true,
      error: 'Failed to fetch assigned jobs',
      jobs: [],
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('employee_history_error')), findsOneWidget);
    expect(find.text('Failed to fetch assigned jobs'), findsOneWidget);
  });

  testWidgets(
      'Renders standalone mode with AppBar when isEmbeddedInTab is false',
      (WidgetTester tester) async {
    await tester.pumpWidget(createEmployeeHistoryScreenApp(
      isEmbeddedInTab: false,
      jobs: [testCompletedJob],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('History & Audit Logs'), findsWidgets);
  });
}
