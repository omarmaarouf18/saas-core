import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-jwt-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;

  @override
  Future<void> fetchUserProfile() async {}
}

class MockChatProviderForTest extends ChatProvider {
  bool createTicketCalled = false;
  String? lastContextIdPassed;
  String? lastUserTokenPassed;
  bool shouldFailCreateTicket = false;
  String failMessage = 'Failed to create ticket';

  MockChatProviderForTest(super.apiClient);

  @override
  Future<Map<String, dynamic>> createTicket({
    required String contextId,
    required String userToken,
  }) async {
    createTicketCalled = true;
    lastContextIdPassed = contextId;
    lastUserTokenPassed = userToken;

    if (shouldFailCreateTicket) {
      throw ApiClientException(failMessage, statusCode: 500);
    }

    return {
      'ticket_id': 'ticket-999',
      'user_id': 'cust-1',
      'context_id': contextId,
      'status': 'open',
    };
  }
}

void main() {
  final activeJob = Job(
    id: 'job-active-ticket-101',
    ownerId: 'owner-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: 'active',
    location: JobLocation(latitude: 30.0, longitude: 31.0),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
  );

  Widget createDialogWidget({
    required MockChatProviderForTest chatProvider,
    MockAuthProviderForTest? authProvider,
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

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: CreateTicketDialog(contextId: activeJob.id),
        ),
      ),
    );
  }

  testWidgets('Renders CreateTicketDialog with reference ID and input fields',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockChat = MockChatProviderForTest(apiClient);

    await tester.pumpWidget(createDialogWidget(chatProvider: mockChat));
    await tester.pumpAndSettle();

    expect(find.text("Open Complaint Ticket"), findsOneWidget);
    expect(find.textContaining("Reference ID: #job-acti"), findsOneWidget);
    expect(find.byKey(const Key('ticket_subject_input')), findsOneWidget);
    expect(find.byKey(const Key('ticket_description_input')), findsOneWidget);
    expect(find.byKey(const Key('submit_ticket_button')), findsOneWidget);
  });

  testWidgets(
      'Validates empty subject and description inputs before submitting',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockChat = MockChatProviderForTest(apiClient);

    await tester.pumpWidget(createDialogWidget(chatProvider: mockChat));
    await tester.pumpAndSettle();

    // Tap submit with empty fields
    await tester.tap(find.byKey(const Key('submit_ticket_button')));
    await tester.pumpAndSettle();

    expect(find.text("Subject is required."), findsOneWidget);
    expect(find.text("Issue details are required."), findsOneWidget);
    expect(mockChat.createTicketCalled, isFalse);
  });

  testWidgets('Calls ChatProvider.createTicket and submits ticket successfully',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockChat = MockChatProviderForTest(apiClient);

    await tester.pumpWidget(createDialogWidget(chatProvider: mockChat));
    await tester.pumpAndSettle();

    // Enter subject and description
    await tester.enterText(
        find.byKey(const Key('ticket_subject_input')), 'Delayed Delivery');
    await tester.enterText(find.byKey(const Key('ticket_description_input')),
        'Driver has not arrived at pickup location for over 30 minutes.');
    await tester.pumpAndSettle();

    // Tap submit button
    await tester.tap(find.byKey(const Key('submit_ticket_button')));
    await tester.pumpAndSettle();

    expect(mockChat.createTicketCalled, isTrue);
    expect(
        mockChat.lastContextIdPassed,
        contains(
            'Job #job-active-ticket-101 - Delayed Delivery: Driver has not arrived at pickup location for over 30 minutes.'));
    expect(mockChat.lastUserTokenPassed, equals('test-jwt-token'));
  });

  testWidgets(
      'Renders error banner inside dialog when ChatProvider.createTicket fails',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockChat = MockChatProviderForTest(apiClient);
    mockChat.shouldFailCreateTicket = true;

    await tester.pumpWidget(createDialogWidget(chatProvider: mockChat));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('ticket_subject_input')), 'Issue Topic');
    await tester.enterText(
        find.byKey(const Key('ticket_description_input')), 'Issue Details');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit_ticket_button')));
    await tester.pumpAndSettle();

    expect(mockChat.createTicketCalled, isTrue);
    expect(find.byKey(const Key('create_ticket_error_banner')), findsOneWidget);
    expect(find.text(ErrorMessages.serverError), findsOneWidget);
  });

  testWidgets(
      'Tapping Open a Complaint Ticket on active job in JobStatusScreen presents CreateTicketDialog',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockChat = MockChatProviderForTest(apiClient);
    final mockAuth = MockAuthProviderForTest(
      apiClient,
      mockUser: UserProfile(
        id: 'cust-1',
        email: 'customer@example.com',
        username: 'CustomerUser',
        role: 'user',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: mockAuth),
          ChangeNotifierProvider<ChatProvider>.value(value: mockChat),
          ChangeNotifierProvider<MarketplaceProvider>(
            create: (_) => MarketplaceProvider(apiClient),
          ),
          ChangeNotifierProvider<NotificationsProvider>(
            create: (_) => NotificationsProvider(apiClient),
          ),
        ],
        child: MaterialApp(
          home: JobStatusScreen(job: activeJob, enablePolling: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final complaintButton =
        find.byKey(const Key('open_complaint_ticket_button'));
    expect(complaintButton, findsOneWidget);

    await tester.ensureVisible(complaintButton);
    await tester.tap(complaintButton);
    await tester.pumpAndSettle();

    expect(find.byType(CreateTicketDialog), findsOneWidget);
  });

  testWidgets('Success snackbar displays the real backend ticket_id',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    // Regression guard: chat-service serializes ComplaintTicket.ID with the
    // JSON tag "ticket_id"; the dialog previously read res['id'] and always
    // rendered an empty Ticket ID.
    final mockChat = MockChatProviderForTest(apiClient);

    await tester.pumpWidget(createDialogWidget(chatProvider: mockChat));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('ticket_subject_input')), 'Broken parcel');
    await tester.enterText(find.byKey(const Key('ticket_description_input')),
        'The parcel arrived crushed.');
    await tester.tap(find.byKey(const Key('submit_ticket_button')));
    // Assert on the frame where the snackbar is visible: pumpAndSettle would
    // run past the snackbar's 2s auto-dismiss timer and remove it.
    await tester.pump();
    await tester.pump();

    expect(mockChat.createTicketCalled, isTrue);
    expect(find.textContaining('Ticket ID: ticket-999'), findsOneWidget,
        reason: 'Snackbar must show the ticket_id returned by the backend');

    await tester.pumpAndSettle();
  });
}
