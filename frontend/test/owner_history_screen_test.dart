import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/screens/owner_history_screen.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/widgets/status_badge.dart';

class MockAuthProviderForHistoryTest extends AuthProvider {
  MockAuthProviderForHistoryTest(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-history-1',
        email: 'owner@example.com',
        username: 'test_owner',
        role: 'owner',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-owner-token';

  @override
  Future<bool> fetchUserProfile() async => true;
}

class MockOwnerProviderForHistoryTest extends OwnerProvider {
  final List<dynamic> mockAuditEntries;
  final List<Job> mockJobs;
  final List<dynamic> mockLedger;
  final bool mockIsLoading;
  final String? mockErrorMessage;

  MockOwnerProviderForHistoryTest(
    super.apiClient, {
    this.mockAuditEntries = const [],
    this.mockJobs = const [],
    this.mockLedger = const [],
    this.mockIsLoading = false,
    this.mockErrorMessage,
  });

  @override
  List<dynamic> get auditLogEntries => mockAuditEntries;

  @override
  List<Job> get ownerJobs => mockJobs;

  @override
  List<dynamic> get ledgerEntries => mockLedger;

  @override
  bool get isLoading => mockIsLoading;

  @override
  String? get error => mockErrorMessage;

  @override
  Future<void> fetchAuditLog({
    required String tenantId,
    required String requesterToken,
  }) async {}

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {}

  @override
  Future<void> fetchDashboardData(String ownerToken) async {}
}

Widget createOwnerHistoryScreenApp({
  bool isEmbeddedInTab = false,
  List<dynamic> auditEntries = const [],
  List<Job> jobs = const [],
  List<dynamic> ledger = const [],
  bool isLoading = false,
  String? errorMessage,
}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => MockAuthProviderForHistoryTest(apiClient)),
      ChangeNotifierProvider<OwnerProvider>(
          create: (_) => MockOwnerProviderForHistoryTest(
                apiClient,
                mockAuditEntries: auditEntries,
                mockJobs: jobs,
                mockLedger: ledger,
                mockIsLoading: isLoading,
                mockErrorMessage: errorMessage,
              )),
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
      home: OwnerHistoryScreen(isEmbeddedInTab: isEmbeddedInTab),
    ),
  );
}

void main() {
  testWidgets('Renders sub-tabs and empty states when no history exists',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHistoryScreenApp(isEmbeddedInTab: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('history_tab_activity')), findsOneWidget);
    expect(find.byKey(const Key('history_tab_jobs')), findsOneWidget);
    expect(find.byKey(const Key('history_tab_ledger')), findsOneWidget);

    // Initial sub-tab: Activity Log empty state
    expect(find.byKey(const Key('empty_audit_log_state')), findsOneWidget);
    expect(find.text('No Employee Activity Found'), findsOneWidget);

    // Switch to Jobs sub-tab
    await tester.tap(find.byKey(const Key('history_tab_jobs')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty_jobs_state')), findsOneWidget);
    expect(find.text('No Completed Jobs Found'), findsOneWidget);

    // Switch to Ledger sub-tab
    await tester.tap(find.byKey(const Key('history_tab_ledger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty_ledger_state')), findsOneWidget);
    expect(find.text('No Ledger Entries Found'), findsOneWidget);
  });

  testWidgets('Renders audit log entries in Activity sub-tab',
      (WidgetTester tester) async {
    final testEntries = [
      {
        'action': 'employee_toggle',
        'details': 'Frozen worker john@example.com',
        'actor_id': 'owner-history-1',
        'timestamp': '2026-08-06T08:00:00Z',
      },
    ];

    await tester.pumpWidget(createOwnerHistoryScreenApp(
      isEmbeddedInTab: true,
      auditEntries: testEntries,
    ));
    await tester.pumpAndSettle();

    expect(find.text('EMPLOYEE TOGGLE'), findsOneWidget);
    expect(find.text('Frozen worker john@example.com'), findsOneWidget);
    expect(find.text('Actor: owner-history-1'), findsOneWidget);
  });

  testWidgets('Renders completed and cancelled jobs in Jobs sub-tab',
      (WidgetTester tester) async {
    final testJobs = [
      Job(
        id: 'job-101',
        ownerId: 'owner-history-1',
        employeeId: 'emp-1',
        userId: 'user-1',
        serviceId: 'srv-1',
        status: 'completed',
        paymentMethod: 'cod',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Job(
        id: 'job-102',
        ownerId: 'owner-history-1',
        employeeId: 'emp-1',
        userId: 'user-2',
        serviceId: 'srv-2',
        status: 'cancelled',
        paymentMethod: 'escrow',
        cancellationReason: 'Customer requested cancellation',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      Job(
        id: 'job-active-ignored',
        ownerId: 'owner-history-1',
        employeeId: 'emp-1',
        userId: 'user-3',
        serviceId: 'srv-3',
        status: 'active',
        paymentMethod: 'cod',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(createOwnerHistoryScreenApp(
      isEmbeddedInTab: true,
      jobs: testJobs,
    ));
    await tester.pumpAndSettle();

    // Switch to Jobs tab
    await tester.tap(find.byKey(const Key('history_tab_jobs')));
    await tester.pumpAndSettle();

    expect(find.text('Job #job-101'), findsOneWidget);
    expect(find.text('Job #job-102'), findsOneWidget);
    expect(find.text('Job #job-active-ignored'),
        findsNothing); // Active job ignored

    expect(find.byType(StatusBadge), findsNWidgets(2));
    expect(
        find.text('Reason: Customer requested cancellation'), findsOneWidget);
  });

  testWidgets('Renders ledger entries in Ledger sub-tab',
      (WidgetTester tester) async {
    final testLedger = [
      {
        'type': 'deposit',
        'amount': 150.0,
        'balance_after': 500.0,
        'description': 'Owner Deposit',
        'job_id': '',
        'timestamp': '2026-08-06T09:00:00Z',
      },
      {
        'type': 'fee_deduction',
        'amount': 5.0,
        'balance_after': 495.0,
        'description': 'Platform Fee',
        'job_id': 'job-101',
        'timestamp': '2026-08-06T09:30:00Z',
      },
    ];

    await tester.pumpWidget(createOwnerHistoryScreenApp(
      isEmbeddedInTab: true,
      ledger: testLedger,
    ));
    await tester.pumpAndSettle();

    // Switch to Ledger tab
    await tester.tap(find.byKey(const Key('history_tab_ledger')));
    await tester.pumpAndSettle();

    expect(find.text('Owner Deposit'), findsOneWidget);
    expect(find.text('Platform Fee'), findsOneWidget);
    expect(find.text(r'+$150.00'), findsOneWidget);
    expect(find.text(r'-$5.00'), findsOneWidget);
  });

  testWidgets('Renders error banner when error occurs',
      (WidgetTester tester) async {
    await tester.pumpWidget(createOwnerHistoryScreenApp(
      isEmbeddedInTab: true,
      errorMessage: 'Network error fetching history',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Network error fetching history'), findsOneWidget);
  });
}
