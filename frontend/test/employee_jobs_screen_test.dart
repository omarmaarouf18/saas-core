import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;
  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;
}

class MockEmployeeJobsProviderForTest extends EmployeeJobsProvider {
  final List<Job> initialJobs;
  final bool shouldFailComplete;
  final String failMessage;
  bool completeJobCalled = false;
  String? completedJobId;
  bool? lastCashCollectedParam;

  MockEmployeeJobsProviderForTest(
    super.apiClient, {
    this.initialJobs = const [],
    this.shouldFailComplete = false,
    this.failMessage = 'Access denied: you are not authorized to complete this job',
  }) {
    _testJobs = List.from(initialJobs);
  }

  late List<Job> _testJobs;

  @override
  List<Job> get jobs => List.unmodifiable(_testJobs);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {
    // No-op for test to keep initialJobs intact
  }

  @override
  Future<void> completeJob(String jobId, {bool cashCollected = false}) async {
    completeJobCalled = true;
    completedJobId = jobId;
    lastCashCollectedParam = cashCollected;

    if (shouldFailComplete) {
      throw ApiClientException(failMessage, statusCode: 403);
    }

    final index = _testJobs.indexWhere((j) => j.id == jobId);
    if (index != -1) {
      final existing = _testJobs[index];
      _testJobs[index] = Job(
        id: existing.id,
        ownerId: existing.ownerId,
        employeeId: existing.employeeId,
        userId: existing.userId,
        serviceId: existing.serviceId,
        status: 'completed',
        location: existing.location,
        currentLocation: existing.currentLocation,
        paymentMethod: existing.paymentMethod,
        cancellationReason: existing.cancellationReason,
        lockedEscrowAmount: existing.lockedEscrowAmount,
        suggestedPrice: existing.suggestedPrice,
        proposedPrice: existing.proposedPrice,
        proposedBy: existing.proposedBy,
        agreedPrice: existing.agreedPrice,
        priceProposalExpiresAt: existing.priceProposalExpiresAt,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }
}

void main() {
  final activeEscrowJob = Job(
    id: 'job-active-escrow-001',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'active',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
  );

  final activeCodJob = Job(
    id: 'job-active-cod-002',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-2',
    serviceId: 'service-2',
    status: 'active',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'cod',
    lockedEscrowAmount: 25.50,
  );

  final pendingJob = Job(
    id: 'job-pending-003',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-3',
    serviceId: 'service-3',
    status: 'pending',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'cod',
  );

  Widget createTestWidget({
    required EmployeeJobsProvider jobsProvider,
    AuthProvider? authProvider,
  }) {
    final apiClient = ApiClient();
    final auth = authProvider ??
        MockAuthProviderForTest(
          apiClient,
          mockUser: UserProfile(
            id: 'emp-1',
            email: 'employee@example.com',
            username: 'EmployeeUser',
            role: 'employee',
          ),
        );

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<EmployeeJobsProvider>.value(
              value: jobsProvider),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => NotificationsProvider(apiClient)),
        ],
        child: const EmployeeJobsScreen(),
      ),
    );
  }

  testWidgets('(a) Complete Job button appears ONLY for active jobs',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [activeEscrowJob, pendingJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // Verify key for activeEscrowJob exists, pendingJob does not
    expect(
        find.byKey(const Key('complete_job_button_job-active-escrow-001')),
        findsOneWidget);
    expect(find.byKey(const Key('complete_job_button_job-pending-003')),
        findsNothing);
  });

  testWidgets('(b) Non-COD job tapping Complete Job shows non-COD dialog copy',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [activeEscrowJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final cardButton =
        find.byKey(const Key('complete_job_button_job-active-escrow-001'));
    await tester.ensureVisible(cardButton);
    await tester.tap(cardButton);
    await tester.pumpAndSettle();

    // Verify non-COD confirmation dialog text
    expect(find.text('Complete Job'), findsNWidgets(3));
    expect(
      find.text('Are you sure you want to mark Job #job-active-escrow-001 as completed?'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel out of dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(jobsProvider.completeJobCalled, isFalse);
  });

  testWidgets(
      '(c) Non-COD job confirmation sends cashCollected: false to provider',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [activeEscrowJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final cardButton =
        find.byKey(const Key('complete_job_button_job-active-escrow-001'));
    await tester.ensureVisible(cardButton);
    await tester.tap(cardButton);
    await tester.pumpAndSettle();

    // Confirm in non-COD dialog
    final dialogConfirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Complete Job'),
    );
    await tester.tap(dialogConfirmButton);
    await tester.pumpAndSettle();

    // Verify provider was called with cashCollected == false
    expect(jobsProvider.completeJobCalled, isTrue);
    expect(jobsProvider.completedJobId, 'job-active-escrow-001');
    expect(jobsProvider.lastCashCollectedParam, isFalse);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets(
      '(d) COD job confirmation shows explicit cash collection dialog copy and sends cashCollected: true',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [activeCodJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final cardButton =
        find.byKey(const Key('complete_job_button_job-active-cod-002'));
    await tester.ensureVisible(cardButton);
    await tester.tap(cardButton);
    await tester.pumpAndSettle();

    // Verify COD-specific confirmation dialog copy
    expect(find.text('Confirm Cash Collection & Complete'), findsOneWidget);
    expect(
      find.textContaining(
          'Confirm you have physically collected the cash payment of \$25.50 (COD) from the customer.'),
      findsOneWidget,
    );
    expect(find.text('Confirm Cash Collected & Complete'), findsOneWidget);

    // Confirm in COD dialog
    final dialogConfirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching:
          find.widgetWithText(ElevatedButton, 'Confirm Cash Collected & Complete'),
    );
    await tester.tap(dialogConfirmButton);
    await tester.pumpAndSettle();

    // Verify provider was called with cashCollected == true
    expect(jobsProvider.completeJobCalled, isTrue);
    expect(jobsProvider.completedJobId, 'job-active-cod-002');
    expect(jobsProvider.lastCashCollectedParam, isTrue);
    expect(find.text('COMPLETED'), findsOneWidget);
  });

  testWidgets('(e) On failure, friendly error message is shown inline',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [activeEscrowJob],
      shouldFailComplete: true,
      failMessage: 'Access denied: you are not authorized to complete this job',
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final cardButton =
        find.byKey(const Key('complete_job_button_job-active-escrow-001'));
    await tester.ensureVisible(cardButton);
    await tester.tap(cardButton);
    await tester.pumpAndSettle();

    // Confirm in dialog
    final dialogConfirmButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Complete Job'),
    );
    await tester.tap(dialogConfirmButton);
    await tester.pumpAndSettle();

    // Verify provider was called and failed
    expect(jobsProvider.completeJobCalled, isTrue);

    // Verify friendly error message is displayed inline
    final errorText = find.text(ErrorMessages.forbidden);
    await tester.ensureVisible(errorText);
    expect(errorText, findsOneWidget);
  });
}
