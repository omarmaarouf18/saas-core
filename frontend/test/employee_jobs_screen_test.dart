import 'dart:io';
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
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_job_map_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';

import 'helpers/stub_tile_http.dart';

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
  bool respondPriceCalled = false;
  String? lastDecision;
  String? lastRespondJobId;
  bool shouldFailRespond = false;
  int failRespondStatus = 403;
  String failRespondMessage = 'forbidden';
  bool proposePriceCalled = false;
  double? lastProposedPrice;
  String? lastProposeJobId;
  bool shouldFailPropose = false;
  int failProposeStatus = 400;
  String failProposeMessage = 'proposal_already_submitted';
  // Refresh-time fault injection (simulates the server truth a refresh
  // would converge onto): inject a customer proposal, or mark cancelled.
  // Applies from the SECOND fetch onward so the initial load still renders
  // the clean propose state and only the post-submit refresh races.
  String? injectProposalJobId;
  String? cancelJobIdOnRefresh;
  int fetchAssignedJobsCalls = 0;

  MockEmployeeJobsProviderForTest(
    super.apiClient, {
    this.initialJobs = const [],
    this.shouldFailComplete = false,
    this.failMessage =
        'Access denied: you are not authorized to complete this job',
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
    // No-op for test to keep initialJobs intact, except refresh-time fault
    // injection flags used by the propose-race tests.
    fetchAssignedJobsCalls++;
    if (fetchAssignedJobsCalls < 2) {
      return;
    }
    if (injectProposalJobId != null) {
      final index = _testJobs.indexWhere((j) => j.id == injectProposalJobId);
      if (index != -1) {
        final existing = _testJobs[index];
        _testJobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: existing.status,
          location: existing.location,
          destination: existing.destination,
          paymentMethod: existing.paymentMethod,
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: 80.0,
          proposedBy: 'customer',
          priceProposalExpiresAt:
              DateTime.now().add(const Duration(minutes: 5)),
        );
      }
    }
    if (cancelJobIdOnRefresh != null) {
      final index = _testJobs.indexWhere((j) => j.id == cancelJobIdOnRefresh);
      if (index != -1) {
        final existing = _testJobs[index];
        _testJobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: 'cancelled',
          location: existing.location,
          destination: existing.destination,
          paymentMethod: existing.paymentMethod,
          cancellationReason: 'price_proposal_expired',
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
        );
      }
    }
    notifyListeners();
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

  @override
  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String employeeToken,
  }) async {
    respondPriceCalled = true;
    lastDecision = decision;
    lastRespondJobId = jobId;

    if (shouldFailRespond) {
      throw ApiClientException(failRespondMessage,
          statusCode: failRespondStatus);
    }

    final index = _testJobs.indexWhere((j) => j.id == jobId);
    if (index != -1) {
      final existing = _testJobs[index];
      if (decision == 'accept') {
        _testJobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: 'active',
          location: existing.location,
          destination: existing.destination,
          currentLocation: existing.currentLocation,
          paymentMethod: existing.paymentMethod,
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
          agreedPrice: existing.proposedPrice ?? existing.suggestedPrice,
          priceProposalExpiresAt: existing.priceProposalExpiresAt,
        );
      } else {
        _testJobs[index] = Job(
          id: existing.id,
          ownerId: existing.ownerId,
          employeeId: existing.employeeId,
          userId: existing.userId,
          serviceId: existing.serviceId,
          status: 'cancelled',
          location: existing.location,
          destination: existing.destination,
          paymentMethod: existing.paymentMethod,
          cancellationReason: 'price_disagreement',
          suggestedPrice: existing.suggestedPrice,
          proposedPrice: existing.proposedPrice,
          proposedBy: existing.proposedBy,
        );
      }
    }
    notifyListeners();
    return index != -1 ? _testJobs[index] : null;
  }

  @override
  Future<Job?> proposePrice({
    required String jobId,
    required double proposedPrice,
    required String employeeToken,
  }) async {
    proposePriceCalled = true;
    lastProposedPrice = proposedPrice;
    lastProposeJobId = jobId;

    if (shouldFailPropose) {
      throw ApiClientException(failProposeMessage,
          statusCode: failProposeStatus);
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
        status: 'awaiting_price_response',
        location: existing.location,
        destination: existing.destination,
        paymentMethod: existing.paymentMethod,
        suggestedPrice: existing.suggestedPrice,
        proposedPrice: proposedPrice,
        proposedBy: 'employee',
        priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    }
    notifyListeners();
    return index != -1 ? _testJobs[index] : null;
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

  final awaitingPriceJob = Job(
    id: 'job-awaiting-price-004',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-4',
    serviceId: 'service-transport-1',
    status: 'awaiting_price_response',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    destination: JobLocation(latitude: 30.1, longitude: 31.1),
    paymentMethod: 'cod',
    suggestedPrice: 90.0,
    proposedPrice: 85.50,
    proposedBy: 'cust-4',
    priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
  );

  // Propose-state fixture: awaiting with a suggested fare but NO proposal
  // yet — the employee may propose first.
  final awaitingPriceNoProposalJob = Job(
    id: 'job-awaiting-noproposal-009',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-9',
    serviceId: 'service-transport-1',
    status: 'awaiting_price_response',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    destination: JobLocation(latitude: 30.1, longitude: 31.1),
    paymentMethod: 'cod',
    suggestedPrice: 90.0,
  );

  // Waiting-state fixture: the employee already proposed; the customer
  // has not responded yet.
  final ownProposedJob = Job(
    id: 'job-own-proposed-008',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-8',
    serviceId: 'service-transport-1',
    status: 'awaiting_price_response',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    destination: JobLocation(latitude: 30.1, longitude: 31.1),
    paymentMethod: 'cod',
    suggestedPrice: 90.0,
    proposedPrice: 95.0,
    proposedBy: 'employee',
    priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
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
          ChangeNotifierProvider<EmployeeJobsProvider>.value(
              value: jobsProvider),
          ChangeNotifierProvider<EmployeeLocationProvider>(
              create: (_) => EmployeeLocationProvider(apiClient)),
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
    expect(find.byKey(const Key('complete_job_button_job-active-escrow-001')),
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
      find.text(
          'Are you sure you want to mark Job #job-active-escrow-001 as completed?'),
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
    expect(find.textContaining('job-active-escrow-001'), findsNothing);
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
      matching: find.widgetWithText(
          ElevatedButton, 'Confirm Cash Collected & Complete'),
    );
    await tester.tap(dialogConfirmButton);
    await tester.pumpAndSettle();

    // Verify provider was called with cashCollected == true
    expect(jobsProvider.completeJobCalled, isTrue);
    expect(jobsProvider.completedJobId, 'job-active-cod-002');
    expect(jobsProvider.lastCashCollectedParam, isTrue);
    expect(find.textContaining('job-active-cod-002'), findsNothing);
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

  testWidgets(
      'Issue-1: awaiting-price job hides Complete but explains fare state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // The Complete gate stays closed: backend CompleteJob 409s non-active.
    expect(find.byKey(const Key('complete_job_button_job-awaiting-price-004')),
        findsNothing);
    // ... and the card communicates why: live proposal state + countdown.
    expect(
        find.byKey(
            const Key('employee_price_pending_panel_job-awaiting-price-004')),
        findsOneWidget);
    expect(find.text('Waiting for fare confirmation'), findsOneWidget);
    expect(find.textContaining('85.50'), findsOneWidget);
    expect(find.textContaining('expires in'), findsOneWidget);
    // Request-cancellation stays available (assignable state).
    expect(
        find.byKey(
            const Key('employee_cancel_job_button_job-awaiting-price-004')),
        findsOneWidget);
    // Issue-2 Option A: destination renders as a map preview, not raw text.
    expect(find.byKey(const Key('job_destination_map_job-awaiting-price-004')),
        findsOneWidget);
  });

  testWidgets('Issue-1: expired proposal shows the expired banner, not a clock',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final expiredJob = Job(
      id: 'job-awaiting-price-005',
      ownerId: 'owner-1',
      employeeId: 'emp-1',
      userId: 'cust-5',
      serviceId: 'service-transport-1',
      status: 'awaiting_price_response',
      location: JobLocation(latitude: 30.0, longitude: 31.0),
      paymentMethod: 'cod',
      suggestedPrice: 90.0,
      proposedPrice: 85.50,
      proposedBy: 'cust-5',
      priceProposalExpiresAt:
          DateTime.now().subtract(const Duration(seconds: 30)),
    );
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [expiredJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('complete_job_button_job-awaiting-price-005')),
        findsNothing);
    expect(find.text('Negotiation Window Expired (5-min limit lapsed)'),
        findsOneWidget);
  });

  testWidgets('Issue-2: job without destination shows fallback, no map slot',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [pendingJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('job_destination_map_job-pending-003')),
        findsNothing);
  });

  testWidgets('Option C: typed note is the primary destination label',
      (WidgetTester tester) async {
    final notedJob = Job(
      id: 'job-noted-006',
      ownerId: 'owner-1',
      employeeId: 'emp-1',
      userId: 'cust-6',
      serviceId: 'service-1',
      status: 'active',
      location: JobLocation(latitude: 30.0, longitude: 31.0),
      destination: JobLocation(
        latitude: 30.1,
        longitude: 31.1,
        addressNote: "beside Ahmed's kiosk",
      ),
      paymentMethod: 'cod',
    );
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [notedJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // Text for quick reading ...
    expect(find.text("beside Ahmed's kiosk"), findsOneWidget);
    // ... map alongside for spatial confirmation (not instead of it).
    expect(find.byKey(const Key('job_destination_map_job-noted-006')),
        findsOneWidget);
    expect(find.byKey(const Key('complete_job_button_job-noted-006')),
        findsOneWidget);
  });

  testWidgets(
      'Price accept: confirm dialog then panel→active, Complete appears',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final acceptBtn =
        find.byKey(const Key('employee_price_accept_job-awaiting-price-004'));
    expect(acceptBtn, findsOneWidget);
    await tester.ensureVisible(acceptBtn);
    await tester.tap(acceptBtn);
    await tester.pumpAndSettle();

    // Accept is a financial commitment: confirmation first (Rule 8).
    expect(find.text('Accept this fare?'), findsOneWidget);
    expect(find.textContaining('85.50'), findsWidgets);
    expect(jobsProvider.respondPriceCalled, isFalse);

    final dialogConfirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Accept Proposal'),
    );
    await tester.tap(dialogConfirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(jobsProvider.respondPriceCalled, isTrue);
    expect(jobsProvider.lastDecision, 'accept');
    expect(jobsProvider.lastRespondJobId, 'job-awaiting-price-004');
    // Server-side active transition reflected: panel gone, Complete shown.
    expect(
        find.byKey(
            const Key('employee_price_pending_panel_job-awaiting-price-004')),
        findsNothing);
    expect(find.byKey(const Key('complete_job_button_job-awaiting-price-004')),
        findsOneWidget);
    expect(find.text('Price proposal accepted! Job is now active.'),
        findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Price decline: immediate, job leaves the assigned list',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final declineBtn =
        find.byKey(const Key('employee_price_decline_job-awaiting-price-004'));
    expect(declineBtn, findsOneWidget);
    await tester.ensureVisible(declineBtn);
    await tester.tap(declineBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // No confirmation for decline (customer + dispatch-offer precedent).
    expect(find.text('Accept this fare?'), findsNothing);
    expect(jobsProvider.respondPriceCalled, isTrue);
    expect(jobsProvider.lastDecision, 'decline');
    // Terminal cancelled/price_disagreement: filtered out of assigned jobs.
    expect(
        find.byKey(
            const Key('employee_price_pending_panel_job-awaiting-price-004')),
        findsNothing);
    expect(
        find.text('Price proposal declined. Job cancelled.'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Expired offer disables both price actions, never calls API',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final expiredJob = Job(
      id: 'job-awaiting-price-005',
      ownerId: 'owner-1',
      employeeId: 'emp-1',
      userId: 'cust-5',
      serviceId: 'service-transport-1',
      status: 'awaiting_price_response',
      location: JobLocation(latitude: 30.0, longitude: 31.0),
      paymentMethod: 'cod',
      suggestedPrice: 90.0,
      proposedPrice: 85.50,
      proposedBy: 'cust-5',
      priceProposalExpiresAt:
          DateTime.now().subtract(const Duration(seconds: 30)),
    );
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [expiredJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // Existing expired-copy state, not a clock.
    expect(find.text('Negotiation Window Expired (5-min limit lapsed)'),
        findsOneWidget);
    final acceptBtn =
        find.byKey(const Key('employee_price_accept_job-awaiting-price-005'));
    final declineBtn =
        find.byKey(const Key('employee_price_decline_job-awaiting-price-005'));
    expect(acceptBtn, findsOneWidget);
    expect(declineBtn, findsOneWidget);
    expect(tester.widget<PrimaryButton>(acceptBtn).onPressed, isNull);
    expect(tester.widget<SecondaryButton>(declineBtn).onPressed, isNull);
    expect(jobsProvider.respondPriceCalled, isFalse);
  });

  testWidgets('Price 403 surfaces the friendly banner with retry',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    )
      ..shouldFailRespond = true
      ..failRespondStatus = 403
      ..failRespondMessage = 'access denied';

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final declineBtn =
        find.byKey(const Key('employee_price_decline_job-awaiting-price-004'));
    await tester.ensureVisible(declineBtn);
    await tester.tap(declineBtn);
    await tester.pumpAndSettle();

    expect(jobsProvider.respondPriceCalled, isTrue);
    final banner =
        find.byKey(const Key('employee_price_error_job-awaiting-price-004'));
    expect(banner, findsOneWidget);
    expect(find.text(ErrorMessages.forbidden), findsOneWidget);
    // Non-lockout failures keep the S5 retry affordance.
    expect(find.descendant(of: banner, matching: find.byType(TextButton)),
        findsOneWidget);
  });

  testWidgets('Price 429 surfaces verbatim lockout text with no retry',
      (WidgetTester tester) async {
    const lockoutText = 'too many requests, locked out for 42 seconds';
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    )
      ..shouldFailRespond = true
      ..failRespondStatus = 429
      ..failRespondMessage = lockoutText;

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final declineBtn =
        find.byKey(const Key('employee_price_decline_job-awaiting-price-004'));
    await tester.ensureVisible(declineBtn);
    await tester.tap(declineBtn);
    await tester.pumpAndSettle();

    final banner =
        find.byKey(const Key('employee_price_error_job-awaiting-price-004'));
    expect(banner, findsOneWidget);
    expect(find.text(lockoutText), findsOneWidget);
    // S5: retries extend the lockout, so no retry affordance renders.
    expect(find.descendant(of: banner, matching: find.byType(TextButton)),
        findsNothing);
  });

  testWidgets('Live map entry opens the employee trip map screen',
      (WidgetTester tester) async {
    // The pushed screen moves the camera on open: stub tile bytes so no
    // sandbox tile failure can escape to the image service (see
    // helpers/stub_tile_http.dart).
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = StubTileHttpOverrides();
    addTearDown(() => HttpOverrides.global = previousOverrides);

    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // Static mini-map preview stays in the card...
    expect(find.byKey(const Key('job_destination_map_job-awaiting-price-004')),
        findsOneWidget);
    // ...and the explicit action navigates to the live screen (mirrors the
    // customer's open_map_tracking_button entry pattern).
    final trackBtn = find
        .byKey(const Key('employee_live_map_button_job-awaiting-price-004'));
    expect(trackBtn, findsOneWidget);
    await tester.ensureVisible(trackBtn);
    await tester.tap(trackBtn);
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeJobMapScreen), findsOneWidget);
    expect(find.text('Live Trip Map'), findsOneWidget);
  });

  testWidgets(
      'Propose panel shows when no proposal exists (respond panel absent)',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key(
            'employee_price_propose_panel_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(find.text('Propose a Fare'), findsOneWidget);
    // Bounds copy mirrors the customer form (suggested 90 → 45–135).
    expect(find.textContaining('45.00'), findsOneWidget);
    expect(find.textContaining('135.00'), findsOneWidget);
    expect(
        find.byKey(
            const Key('employee_propose_input_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.byKey(
            const Key('employee_propose_submit_job-awaiting-noproposal-009')),
        findsOneWidget);
    // Respond + waiting states stay hidden.
    expect(
        find.byKey(const Key(
            'employee_price_pending_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(
        find.byKey(const Key(
            'employee_price_waiting_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(jobsProvider.proposePriceCalled, isFalse);
  });

  testWidgets('Out-of-range input shows bounds error, no API call',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '200');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    expect(find.text('Price must be between \$45.00 and \$135.00'),
        findsOneWidget);
    expect(jobsProvider.proposePriceCalled, isFalse);
  });

  testWidgets('Non-numeric input shows valid-number error, no API call',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, 'abc');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid number'), findsOneWidget);
    expect(jobsProvider.proposePriceCalled, isFalse);
  });

  testWidgets('Propose success transitions the card to the waiting panel',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(jobsProvider.proposePriceCalled, isTrue);
    expect(jobsProvider.lastProposeJobId, 'job-awaiting-noproposal-009');
    expect(jobsProvider.lastProposedPrice, 85.5);
    // Correct next state: own proposal is with the customer — waiting
    // panel (countdown, no actions), propose + respond panels gone.
    expect(
        find.byKey(const Key(
            'employee_price_waiting_panel_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.text('Waiting for response to your proposal...'), findsOneWidget);
    expect(
        find.byKey(const Key(
            'employee_price_propose_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(
        find.byKey(const Key(
            'employee_price_pending_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(find.text('Price proposal sent — waiting for the customer.'),
        findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Propose 409 race shows raced copy and refresh reveals the respond panel',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    )
      ..shouldFailPropose = true
      ..failProposeStatus = 409
      ..failProposeMessage = 'job_state_changed'
      ..injectProposalJobId = 'job-awaiting-noproposal-009';

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    expect(jobsProvider.proposePriceCalled, isTrue);
    // The refreshed server truth carries the customer's proposal: the
    // raced notice renders above the converged respond actions.
    expect(
        find.byKey(const Key(
            'employee_proposal_raced_notice_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.text('The customer already sent a price — respond to it instead.'),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'employee_price_pending_panel_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.byKey(
            const Key('employee_price_accept_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'employee_price_propose_panel_job-awaiting-noproposal-009')),
        findsNothing);

    // Acting on the converged panel clears the notice: accept the
    // customer's proposal through the standard confirm flow.
    await tester.tap(find
        .byKey(const Key('employee_price_accept_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Accept Proposal'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        find.byKey(const Key(
            'employee_proposal_raced_notice_job-awaiting-noproposal-009')),
        findsNothing);
    expect(
        find.byKey(
            const Key('complete_job_button_job-awaiting-noproposal-009')),
        findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('Propose 400 with a terminal refresh shows state-changed copy',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    )
      ..shouldFailPropose = true
      ..failProposeStatus = 400
      ..failProposeMessage = 'invalid_job_status'
      ..cancelJobIdOnRefresh = 'job-awaiting-noproposal-009';

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    // Terminal refresh: the card drops from the assigned list entirely.
    expect(
        find.byKey(const Key(
            'employee_price_propose_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(
        find.byKey(const Key(
            'employee_price_pending_panel_job-awaiting-noproposal-009')),
        findsNothing);
  });

  testWidgets('Propose 400 on a still-clean job falls back to bounds copy',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    )
      ..shouldFailPropose = true
      ..failProposeStatus = 400
      ..failProposeMessage = 'invalid_proposed_price';

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    final banner = find
        .byKey(const Key('employee_propose_error_job-awaiting-noproposal-009'));
    expect(banner, findsOneWidget);
    expect(
        find.text('Price must be between \$45.00 and \$135.00'), findsWidgets);
    // Actionable failure keeps its retry (re-submits the same input).
    expect(find.descendant(of: banner, matching: find.byType(TextButton)),
        findsOneWidget);
  });

  testWidgets('Propose 429 surfaces verbatim lockout text with no retry',
      (WidgetTester tester) async {
    const lockoutText = 'too many requests, locked out for 42 seconds';
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    )
      ..shouldFailPropose = true
      ..failProposeStatus = 429
      ..failProposeMessage = lockoutText;

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    final banner = find
        .byKey(const Key('employee_propose_error_job-awaiting-noproposal-009'));
    expect(banner, findsOneWidget);
    expect(find.text(lockoutText), findsOneWidget);
    expect(find.descendant(of: banner, matching: find.byType(TextButton)),
        findsNothing);
  });

  testWidgets('Propose 403 surfaces the friendly banner',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [awaitingPriceNoProposalJob],
    )
      ..shouldFailPropose = true
      ..failProposeStatus = 403
      ..failProposeMessage = 'access denied';

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    final input = find.descendant(
      of: find.byKey(
          const Key('employee_propose_input_job-awaiting-noproposal-009')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '85.5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(
        const Key('employee_propose_submit_job-awaiting-noproposal-009')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(
            const Key('employee_propose_error_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(find.text(ErrorMessages.forbidden), findsOneWidget);
  });

  testWidgets(
      'Propose vs respond vs waiting panels are mutually exclusive per job',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      initialJobs: [
        awaitingPriceNoProposalJob,
        awaitingPriceJob,
        ownProposedJob,
      ],
    );

    await tester.pumpWidget(createTestWidget(jobsProvider: jobsProvider));
    await tester.pumpAndSettle();

    // No-proposal job: propose form only.
    expect(
        find.byKey(const Key(
            'employee_price_propose_panel_job-awaiting-noproposal-009')),
        findsOneWidget);
    expect(
        find.byKey(const Key(
            'employee_price_pending_panel_job-awaiting-noproposal-009')),
        findsNothing);
    expect(
        find.byKey(const Key(
            'employee_price_waiting_panel_job-awaiting-noproposal-009')),
        findsNothing);

    // Customer-proposed job: respond actions only.
    expect(
        find.byKey(
            const Key('employee_price_pending_panel_job-awaiting-price-004')),
        findsOneWidget);
    expect(
        find.byKey(
            const Key('employee_price_propose_panel_job-awaiting-price-004')),
        findsNothing);
    expect(
        find.byKey(
            const Key('employee_price_waiting_panel_job-awaiting-price-004')),
        findsNothing);

    // Own-proposed job: waiting notice only (countdown, no actions).
    expect(
        find.byKey(
            const Key('employee_price_waiting_panel_job-own-proposed-008')),
        findsOneWidget);
    expect(
        find.text('Waiting for response to your proposal...'), findsOneWidget);
    expect(
        find.byKey(
            const Key('employee_price_propose_panel_job-own-proposed-008')),
        findsNothing);
    expect(
        find.byKey(
            const Key('employee_price_pending_panel_job-own-proposed-008')),
        findsNothing);
    expect(find.byKey(const Key('employee_price_accept_job-own-proposed-008')),
        findsNothing);
    expect(find.byKey(const Key('employee_price_decline_job-own-proposed-008')),
        findsNothing);
  });
}
