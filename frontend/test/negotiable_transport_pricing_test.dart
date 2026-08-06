import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/screens/job_status_screen.dart';

class MockAuthProvider extends AuthProvider {
  MockAuthProvider(super.apiClient);

  @override
  String? get token => 'test-mock-token';

  @override
  UserProfile? get user => UserProfile(
        id: 'customer-1',
        email: 'customer@example.com',
        username: 'customer1',
        role: 'customer',
      );
}

class MockMarketplaceProvider extends MarketplaceProvider {
  Job testJob;
  bool mockConflictError;
  bool proposePriceCalled = false;
  double? lastProposedPrice;
  bool respondPriceCalled = false;
  String? lastDecision;
  bool fetchJobStatusCalled = false;

  MockMarketplaceProvider(
    super.apiClient, {
    required this.testJob,
    this.mockConflictError = false,
  });

  @override
  Future<Job?> proposePrice({
    required String jobId,
    required double proposedPrice,
    required String userToken,
  }) async {
    proposePriceCalled = true;
    lastProposedPrice = proposedPrice;
    if (mockConflictError) {
      throw ApiClientException('job_state_changed', statusCode: 409);
    }
    testJob = Job(
      id: testJob.id,
      ownerId: testJob.ownerId,
      employeeId: testJob.employeeId,
      userId: testJob.userId,
      serviceId: testJob.serviceId,
      status: 'awaiting_price_response',
      location: testJob.location,
      paymentMethod: testJob.paymentMethod,
      suggestedPrice: testJob.suggestedPrice,
      proposedPrice: proposedPrice,
      proposedBy: 'customer',
      priceProposalExpiresAt: testJob.priceProposalExpiresAt,
    );
    notifyListeners();
    return testJob;
  }

  @override
  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String userToken,
  }) async {
    respondPriceCalled = true;
    lastDecision = decision;
    if (mockConflictError) {
      throw ApiClientException('job_state_changed', statusCode: 409);
    }
    final newStatus = decision == 'accept' ? 'active' : 'cancelled';
    testJob = Job(
      id: testJob.id,
      ownerId: testJob.ownerId,
      employeeId: testJob.employeeId,
      userId: testJob.userId,
      serviceId: testJob.serviceId,
      status: newStatus,
      location: testJob.location,
      paymentMethod: testJob.paymentMethod,
      suggestedPrice: testJob.suggestedPrice,
      proposedPrice: testJob.proposedPrice,
      proposedBy: testJob.proposedBy,
      agreedPrice: decision == 'accept' ? testJob.proposedPrice : null,
      cancellationReason: decision == 'decline' ? 'price_disagreement' : null,
    );
    notifyListeners();
    return testJob;
  }

  @override
  Future<Job?> fetchJobStatus(String jobId, String userToken) async {
    fetchJobStatusCalled = true;
    return testJob;
  }
}

void main() {
  final baseJob = Job(
    id: 'job-transport-101',
    ownerId: 'owner-1',
    employeeId: 'employee-1',
    userId: 'customer-1',
    serviceId: 'service-transport-1',
    status: 'awaiting_price_response',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    suggestedPrice: 20.0,
    priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );

  Widget createTestWidget({
    required Job job,
    required MarketplaceProvider marketplaceProvider,
    required AuthProvider authProvider,
  }) {
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
          ChangeNotifierProvider<MarketplaceProvider>.value(
              value: marketplaceProvider),
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: JobStatusScreen(job: job, enablePolling: false),
      ),
    );
  }

  testWidgets('1. Proposing a price submits counter-offer successfully',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(apiClient);
    final marketplaceProvider =
        MockMarketplaceProvider(apiClient, testJob: baseJob);

    await tester.pumpWidget(createTestWidget(
      job: baseJob,
      marketplaceProvider: marketplaceProvider,
      authProvider: authProvider,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Price Negotiation'), findsOneWidget);
    expect(find.byKey(const Key('counter_offer_input')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('counter_offer_input')),
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('counter_offer_input')), '25.0');
    await tester.scrollUntilVisible(
      find.byKey(const Key('submit_proposal_button')),
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 150));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit_proposal_button')));
    await tester.pump();
    await tester.pump();

    expect(marketplaceProvider.proposePriceCalled, isTrue);
    expect(marketplaceProvider.lastProposedPrice, 25.0);
    expect(find.text('Counter-offer submitted successfully!'), findsOneWidget);
  });

  testWidgets('2. Accepting an incoming proposal transitions job state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(apiClient);

    final jobWithProposal = Job(
      id: baseJob.id,
      ownerId: baseJob.ownerId,
      employeeId: baseJob.employeeId,
      userId: baseJob.userId,
      serviceId: baseJob.serviceId,
      status: 'awaiting_price_response',
      location: baseJob.location,
      paymentMethod: baseJob.paymentMethod,
      suggestedPrice: 20.0,
      proposedPrice: 25.0,
      proposedBy: 'employee',
      priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
    );

    final marketplaceProvider =
        MockMarketplaceProvider(apiClient, testJob: jobWithProposal);

    await tester.pumpWidget(createTestWidget(
      job: jobWithProposal,
      marketplaceProvider: marketplaceProvider,
      authProvider: authProvider,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('incoming_proposal_card')), findsOneWidget);
    expect(find.byKey(const Key('proposed_price_text')), findsOneWidget);
    expect(find.text('\$25.00'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('accept_proposal_button')));
    await tester.tap(find.byKey(const Key('accept_proposal_button')));
    await tester.pump();
    await tester.pump();

    expect(marketplaceProvider.respondPriceCalled, isTrue);
    expect(marketplaceProvider.lastDecision, 'accept');
    expect(find.text('Price proposal accepted! Job is now active.'),
        findsOneWidget);
  });

  testWidgets('3. Declining an incoming proposal cancels the job',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(apiClient);

    final jobWithProposal = Job(
      id: baseJob.id,
      ownerId: baseJob.ownerId,
      employeeId: baseJob.employeeId,
      userId: baseJob.userId,
      serviceId: baseJob.serviceId,
      status: 'awaiting_price_response',
      location: baseJob.location,
      paymentMethod: baseJob.paymentMethod,
      suggestedPrice: 20.0,
      proposedPrice: 25.0,
      proposedBy: 'employee',
      priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
    );

    final marketplaceProvider =
        MockMarketplaceProvider(apiClient, testJob: jobWithProposal);

    await tester.pumpWidget(createTestWidget(
      job: jobWithProposal,
      marketplaceProvider: marketplaceProvider,
      authProvider: authProvider,
    ));
    await tester.pump();
    await tester.pump();

    await tester
        .ensureVisible(find.byKey(const Key('decline_proposal_button')));
    await tester.tap(find.byKey(const Key('decline_proposal_button')));
    await tester.pump();
    await tester.pump();

    expect(marketplaceProvider.respondPriceCalled, isTrue);
    expect(marketplaceProvider.lastDecision, 'decline');
    expect(
        find.text('Price proposal declined. Job cancelled.'), findsOneWidget);
  });

  testWidgets('4. Handling 409 conflict state shows clear user message',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(apiClient);

    final jobWithProposal = Job(
      id: baseJob.id,
      ownerId: baseJob.ownerId,
      employeeId: baseJob.employeeId,
      userId: baseJob.userId,
      serviceId: baseJob.serviceId,
      status: 'awaiting_price_response',
      location: baseJob.location,
      paymentMethod: baseJob.paymentMethod,
      suggestedPrice: 20.0,
      proposedPrice: 25.0,
      proposedBy: 'employee',
      priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
    );

    final marketplaceProvider = MockMarketplaceProvider(
      apiClient,
      testJob: jobWithProposal,
      mockConflictError: true,
    );

    await tester.pumpWidget(createTestWidget(
      job: jobWithProposal,
      marketplaceProvider: marketplaceProvider,
      authProvider: authProvider,
    ));
    await tester.pump();
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('accept_proposal_button')));
    await tester.tap(find.byKey(const Key('accept_proposal_button')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
          'Job state changed — the other party already acted or status changed.'),
      findsOneWidget,
    );
  });

  testWidgets('5. Expiry state displays expired banner when window lapses',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(apiClient);

    final expiredJob = Job(
      id: baseJob.id,
      ownerId: baseJob.ownerId,
      employeeId: baseJob.employeeId,
      userId: baseJob.userId,
      serviceId: baseJob.serviceId,
      status: 'cancelled',
      cancellationReason: 'price_proposal_expired',
      location: baseJob.location,
      paymentMethod: baseJob.paymentMethod,
      suggestedPrice: 20.0,
      priceProposalExpiresAt:
          DateTime.now().subtract(const Duration(minutes: 2)),
    );

    final marketplaceProvider =
        MockMarketplaceProvider(apiClient, testJob: expiredJob);

    await tester.pumpWidget(createTestWidget(
      job: expiredJob,
      marketplaceProvider: marketplaceProvider,
      authProvider: authProvider,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('negotiation_expired_banner')), findsOneWidget);
    expect(find.text('Negotiation Window Expired (5-min limit lapsed)'),
        findsOneWidget);
  });
}
