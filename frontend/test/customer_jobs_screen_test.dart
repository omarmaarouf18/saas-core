import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-customer-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;

  @override
  Future<void> fetchUserProfile() async {}
}

class MockMarketplaceProviderForTest extends MarketplaceProvider {
  List<Job> mockCustomerJobs = [];
  bool mockIsLoading = false;
  String? mockError;
  bool fetchCustomerJobsCalled = false;
  String? lastTokenPassed;

  MockMarketplaceProviderForTest(super.apiClient);

  @override
  List<Job> get customerJobs => mockCustomerJobs;

  @override
  bool get isLoading => mockIsLoading;

  @override
  String? get error => mockError;

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async {
    fetchCustomerJobsCalled = true;
    lastTokenPassed = userToken;
    return mockCustomerJobs;
  }

  @override
  Future<void> fetchServices({
    bool nearBy = true,
    double lat = 30.0444,
    double lon = 31.2357,
    double radius = 50.0,
    String sortBy = 'price',
  }) async {}
}

void main() {
  final sampleJobPending = Job(
    id: 'job-cust-101',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-delivery-1',
    status: 'pending',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    suggestedPrice: 25.0,
  );

  final sampleJobActive = Job(
    id: 'job-cust-102',
    ownerId: 'owner-1',
    employeeId: 'emp-2',
    userId: 'cust-1',
    serviceId: 'service-ride-1',
    status: 'active',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'escrow',
    agreedPrice: 40.0,
  );

  final sampleJobCancelled = Job(
    id: 'job-cust-103',
    ownerId: 'owner-1',
    employeeId: null,
    userId: 'cust-1',
    serviceId: 'service-shipping-1',
    status: 'cancelled',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    cancellationReason: 'Customer requested cancellation',
  );

  Widget createWidgetUnderTest({
    required MockMarketplaceProviderForTest marketplaceProvider,
    MockAuthProviderForTest? authProvider,
  }) {
    final apiClient = ApiClient();
    final auth = authProvider ??
        MockAuthProviderForTest(
          apiClient,
          mockUser: UserProfile(
            id: 'cust-1',
            email: 'customer@example.com',
            username: 'CustomerTest',
            role: 'user',
          ),
        );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<MarketplaceProvider>.value(
            value: marketplaceProvider),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient),
        ),
      ],
      child: const MaterialApp(
        home: CustomerJobsScreen(),
      ),
    );
  }

  testWidgets('Renders loading state while customer jobs are being loaded',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    mockMarketplace.mockIsLoading = true;
    mockMarketplace.mockCustomerJobs = [];

    await tester.pumpWidget(createWidgetUnderTest(
      marketplaceProvider: mockMarketplace,
    ));

    expect(find.byKey(const Key('customer_jobs_loading')), findsOneWidget);
    expect(find.text("Loading orders..."), findsOneWidget);
  });

  testWidgets('Renders empty state when customer has zero jobs',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    mockMarketplace.mockIsLoading = false;
    mockMarketplace.mockCustomerJobs = [];

    await tester.pumpWidget(createWidgetUnderTest(
      marketplaceProvider: mockMarketplace,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_jobs_empty_state')), findsOneWidget);
    expect(find.text("No Orders Found"), findsOneWidget);
    expect(
        find.text(
            "You haven't placed any orders yet. Explore services in the marketplace to get started."),
        findsOneWidget);
  });

  testWidgets(
      'Renders customer job cards with correct status badges and details when jobs exist',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    mockMarketplace.mockIsLoading = false;
    mockMarketplace.mockCustomerJobs = [
      sampleJobPending,
      sampleJobActive,
      sampleJobCancelled,
    ];

    await tester.pumpWidget(createWidgetUnderTest(
      marketplaceProvider: mockMarketplace,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_jobs_list')), findsOneWidget);
    expect(find.byKey(Key('customer_job_card_${sampleJobPending.id}')),
        findsOneWidget);
    expect(find.byKey(Key('customer_job_card_${sampleJobActive.id}')),
        findsOneWidget);
    expect(find.byKey(Key('customer_job_card_${sampleJobCancelled.id}')),
        findsOneWidget);

    // Verify order IDs
    expect(find.text("Order #job-cust"), findsNWidgets(3));

    // Verify prices & payment methods
    expect(find.text("\$25.00"), findsOneWidget);
    expect(find.text("\$40.00"), findsOneWidget);
    expect(find.text("Payment: COD"), findsNWidgets(2));
    expect(find.text("Payment: ESCROW"), findsOneWidget);

    // Verify cancellation reason
    expect(
        find.text("Reason: Customer requested cancellation"), findsOneWidget);
  });

  testWidgets('Renders inline error banner when fetchCustomerJobs sets error',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    mockMarketplace.mockIsLoading = false;
    mockMarketplace.mockCustomerJobs = [];
    mockMarketplace.mockError = "Failed to fetch customer orders from server.";

    await tester.pumpWidget(createWidgetUnderTest(
      marketplaceProvider: mockMarketplace,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer_jobs_error_banner')), findsOneWidget);
    expect(find.text("Failed to fetch customer orders from server."),
        findsOneWidget);
    expect(find.byKey(const Key('retry_customer_jobs_button')), findsOneWidget);
  });

  testWidgets('Tapping a job card navigates to JobStatusScreen',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    mockMarketplace.mockIsLoading = false;
    mockMarketplace.mockCustomerJobs = [sampleJobPending];

    await tester.pumpWidget(createWidgetUnderTest(
      marketplaceProvider: mockMarketplace,
    ));
    await tester.pumpAndSettle();

    // Tap job card
    await tester
        .tap(find.byKey(Key('customer_job_card_${sampleJobPending.id}')));
    await tester.pumpAndSettle();

    // Confirm navigation to JobStatusScreen
    expect(find.byType(JobStatusScreen), findsOneWidget);
  });

  testWidgets(
      'Navigating via My Orders button in CustomerMarketplaceScreen opens CustomerJobsScreen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final apiClient = ApiClient();
    final mockMarketplace = MockMarketplaceProviderForTest(apiClient);
    final mockAuth = MockAuthProviderForTest(
      apiClient,
      mockUser: UserProfile(
        id: 'cust-1',
        email: 'customer@example.com',
        username: 'CustomerTest',
        role: 'user',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ChangeNotifierProvider<MarketplaceProvider>.value(
              value: mockMarketplace),
          ChangeNotifierProvider<NotificationsProvider>(
            create: (_) => NotificationsProvider(apiClient),
          ),
        ],
        child: const MaterialApp(
          home: CustomerMarketplaceScreen(isEmbeddedInTab: true),
        ),
      ),
    );
    await tester.pump();

    // Verify my_orders_button is removed from top app bar when embedded in tab
    expect(find.byKey(const Key('my_orders_button')), findsNothing);
  });
}
