import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;
  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;

  @override
  Future<void> fetchUserProfile() async {}
}

class MockMarketplaceProviderForTest extends MarketplaceProvider {
  bool cancelJobCalled = false;
  String? lastCancelledJobId;
  String? lastCancelledReason;
  bool shouldFailCancel = false;
  String failMessage = 'Access denied';

  MockMarketplaceProviderForTest(super.apiClient);

  @override
  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String userToken,
  }) async {
    cancelJobCalled = true;
    lastCancelledJobId = jobId;
    lastCancelledReason = reason;

    if (shouldFailCancel) {
      throw ApiClientException(failMessage, statusCode: 403);
    }

    return {'message': 'job cancelled successfully', 'status': 'cancelled'};
  }
}

class MockOwnerProviderForTest extends OwnerProvider {
  List<Job> mockOwnerJobs;
  bool cancelJobCalled = false;
  String? lastCancelledJobId;
  String? lastCancelledReason;
  bool shouldFailCancel = false;
  String failMessage = 'Access denied';

  MockOwnerProviderForTest(super.apiClient, {this.mockOwnerJobs = const []});

  @override
  List<Job> get ownerJobs => mockOwnerJobs;

  @override
  Future<void> fetchDashboardData(String tenantId) async {}

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {}

  @override
  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String ownerToken,
  }) async {
    cancelJobCalled = true;
    lastCancelledJobId = jobId;
    lastCancelledReason = reason;

    if (shouldFailCancel) {
      throw ApiClientException(failMessage, statusCode: 403);
    }

    return {'message': 'job cancelled successfully', 'status': 'cancelled'};
  }
}

void main() {
  final pendingJob = Job(
    id: 'job-pending-101',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'pending',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 40.0,
  );

  final activeJob = Job(
    id: 'job-active-102',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'active',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
  );

  final completedJob = Job(
    id: 'job-completed-103',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'completed',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
  );

  final cancelledJob = Job(
    id: 'job-cancelled-104',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'cancelled',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
  );

  Widget createCustomerWidget({
    required Job job,
    required MarketplaceProvider marketplaceProvider,
    AuthProvider? authProvider,
  }) {
    final apiClient = ApiClient();
    final auth = authProvider ??
        MockAuthProviderForTest(
          apiClient,
          mockUser: UserProfile(
            id: 'cust-1',
            email: 'customer@example.com',
            username: 'CustomerUser',
            role: 'user',
          ),
        );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<MarketplaceProvider>.value(
              value: marketplaceProvider),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => NotificationsProvider(apiClient)),
        ],
        child: JobStatusScreen(job: job, enablePolling: false),
      ),
    );
  }

  Widget createOwnerWidget({
    required List<Job> ownerJobs,
    required OwnerProvider ownerProvider,
    AuthProvider? authProvider,
  }) {
    final apiClient = ApiClient();
    final auth = authProvider ??
        MockAuthProviderForTest(
          apiClient,
          mockUser: UserProfile(
            id: 'owner-1',
            email: 'owner@example.com',
            username: 'OwnerUser',
            role: 'owner',
          ),
        );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
          ChangeNotifierProvider<MarketplaceProvider>(
              create: (_) => MarketplaceProvider(apiClient)),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => NotificationsProvider(apiClient)),
        ],
        child: const HomeScreen(initialTabIndex: 0),
      ),
    );
  }

  testWidgets('(a) Cancel button is ABSENT for completed and cancelled jobs',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mpProvider = MockMarketplaceProviderForTest(apiClient);
    final ownerProvider = MockOwnerProviderForTest(
      apiClient,
      mockOwnerJobs: [completedJob, cancelledJob],
    );

    // Customer JobStatusScreen test for completed job
    await tester.pumpWidget(createCustomerWidget(
      job: completedJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel_job_button')), findsNothing);
    expect(find.byKey(const Key('open_complaint_ticket_button')), findsNothing);

    // Customer JobStatusScreen test for cancelled job
    await tester.pumpWidget(createCustomerWidget(
      job: cancelledJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel_job_button')), findsNothing);

    // Owner HomeScreen test for completed and cancelled jobs
    await tester.pumpWidget(createOwnerWidget(
      ownerJobs: [completedJob, cancelledJob],
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel_owner_job_button_job-completed-103')),
        findsNothing);
    expect(find.byKey(const Key('cancel_owner_job_button_job-cancelled-104')),
        findsNothing);
  });

  testWidgets(
      '(b) Reason field is required — confirm button is disabled when empty',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mpProvider = MockMarketplaceProviderForTest(apiClient);

    await tester.pumpWidget(createCustomerWidget(
      job: pendingJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();

    final cancelButton = find.byKey(const Key('cancel_job_button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    // Dialog title exists
    expect(find.text('Cancel Job #job-pending-101'), findsOneWidget);

    final confirmButton = find.byKey(const Key('confirm_cancel_button'));
    expect(confirmButton, findsOneWidget);

    // Verify confirm button is initially DISABLED (reason field is empty)
    PrimaryButton buttonWidget = tester.widget(confirmButton);
    expect(buttonWidget.onPressed, isNull);

    // Enter whitespace reason only
    await tester.enterText(find.byKey(const Key('cancel_reason_input')), '   ');
    await tester.pumpAndSettle();
    buttonWidget = tester.widget(confirmButton);
    expect(buttonWidget.onPressed, isNull);

    // Enter valid reason text
    await tester.enterText(
        find.byKey(const Key('cancel_reason_input')), 'Valid reason');
    await tester.pumpAndSettle();
    buttonWidget = tester.widget(confirmButton);
    expect(buttonWidget.onPressed, isNotNull);
  });

  testWidgets('(c) Owner CAN cancel an active job',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final ownerProvider = MockOwnerProviderForTest(
      apiClient,
      mockOwnerJobs: [activeJob],
    );

    await tester.pumpWidget(createOwnerWidget(
      ownerJobs: [activeJob],
      ownerProvider: ownerProvider,
    ));
    await tester.pumpAndSettle();

    final cancelButton =
        find.byKey(const Key('cancel_owner_job_button_job-active-102'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    // Enter reason and confirm
    await tester.enterText(find.byKey(const Key('cancel_reason_input')),
        'Owner cancelling active job');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(ownerProvider.cancelJobCalled, isTrue);
    expect(ownerProvider.lastCancelledJobId, 'job-active-102');
    expect(ownerProvider.lastCancelledReason, 'Owner cancelling active job');
  });

  testWidgets(
      '(d) Customer CANNOT cancel an active job and sees Complaint Ticket button instead',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mpProvider = MockMarketplaceProviderForTest(apiClient);

    await tester.pumpWidget(createCustomerWidget(
      job: activeJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();

    // Verify "Cancel Job" button does NOT exist for customer on active job
    expect(find.byKey(const Key('cancel_job_button')), findsNothing);

    // Verify "Open a Complaint Ticket" button IS displayed instead
    final complaintButton =
        find.byKey(const Key('open_complaint_ticket_button'));
    await tester.ensureVisible(complaintButton);
    expect(complaintButton, findsOneWidget);

    await tester.tap(complaintButton);
    await tester.pumpAndSettle();

    // CreateTicketDialog displayed upon clicking complaint button
    expect(find.byType(CreateTicketDialog), findsOneWidget);
    expect(mpProvider.cancelJobCalled, isFalse);
  });

  testWidgets('(e) Customer CAN cancel a pending job',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mpProvider = MockMarketplaceProviderForTest(apiClient);

    await tester.pumpWidget(createCustomerWidget(
      job: pendingJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();

    final cancelButton = find.byKey(const Key('cancel_job_button'));
    expect(cancelButton, findsOneWidget);
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('cancel_reason_input')), 'Customer changed mind');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(mpProvider.cancelJobCalled, isTrue);
    expect(mpProvider.lastCancelledJobId, 'job-pending-101');
    expect(mpProvider.lastCancelledReason, 'Customer changed mind');
  });

  testWidgets(
      '(f) On cancellation failure, friendly error is shown inline in dialog',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mpProvider = MockMarketplaceProviderForTest(apiClient)
      ..shouldFailCancel = true
      ..failMessage =
          'Access denied: you are not authorized to cancel this job';

    await tester.pumpWidget(createCustomerWidget(
      job: pendingJob,
      marketplaceProvider: mpProvider,
    ));
    await tester.pumpAndSettle();

    final cancelButton = find.byKey(const Key('cancel_job_button'));
    await tester.ensureVisible(cancelButton);
    await tester.tap(cancelButton);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('cancel_reason_input')), 'Test reason');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirm_cancel_button')));
    await tester.pumpAndSettle();

    expect(mpProvider.cancelJobCalled, isTrue);
    // Dialog remains open showing friendly error message
    expect(find.text(ErrorMessages.forbidden), findsOneWidget);
  });
}
