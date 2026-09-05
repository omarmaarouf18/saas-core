import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/support_ticket.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/customer_tickets_screen.dart';
import 'package:frontend/screens/notifications_screen.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/ticket_chat_screen.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';
import 'package:frontend/widgets/status_badge.dart';
import 'package:provider/provider.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(
    super.apiClient, {
    this.mockUser,
    this.mockToken = 'test-token',
  });

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;
}

class MockChatProviderForTest extends ChatProvider {
  List<SupportTicket> mockTickets;
  List<ChatMessage> mockMessages;
  bool fetchCustomerTicketsCalled = false;
  String? lastSubscribedChannel;
  String? lastMessageSent;
  bool disconnectCalled = false;

  MockChatProviderForTest(
    super.apiClient, {
    this.mockTickets = const [],
    this.mockMessages = const [],
  }) : super();

  @override
  List<SupportTicket> get customerTickets => mockTickets;

  @override
  List<ChatMessage> get messages => mockMessages;

  @override
  bool get isConnected => true;

  @override
  bool get isLoadingTickets => false;

  @override
  String? get ticketsError => null;

  @override
  Future<List<SupportTicket>> fetchCustomerTickets({
    bool refresh = false,
    int page = 1,
    int limit = 20,
  }) async {
    fetchCustomerTicketsCalled = true;
    return mockTickets;
  }

  @override
  Future<void> fetchChannelHistory(String channel, String token) async {
    lastSubscribedChannel = channel;
  }

  @override
  void connectAndSubscribeChannel(String channel, String token) {
    lastSubscribedChannel = channel;
  }

  @override
  Future<void> sendMessage(String content) async {
    lastMessageSent = content;
    final newMsg = ChatMessage(
      channel: lastSubscribedChannel ?? '',
      senderId: 'user-1',
      senderUsername: 'AliceCustomer',
      content: content,
      type: 'chat',
    );
    mockMessages = [...mockMessages, newMsg];
    notifyListeners();
  }

  void addMessage(ChatMessage msg) {
    mockMessages = [...mockMessages, msg];
    notifyListeners();
  }

  @override
  void disconnect() {
    disconnectCalled = true;
  }
}

class MockNotificationsProviderForTickets extends NotificationsProvider {
  final List<NotificationModel> _mockList;

  MockNotificationsProviderForTickets(super.apiClient, this._mockList);

  @override
  List<NotificationModel> get notifications => _mockList;

  @override
  bool get isConnected => true;

  @override
  Future<void> fetchHistory({bool refresh = false, int limit = 30}) async {}

  @override
  Future<void> markAsRead(String id) async {}
}

Widget buildTestApp({
  required Widget home,
  required AuthProvider authProvider,
  required ChatProvider chatProvider,
  NotificationsProvider? notificationsProvider,
}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
      ChangeNotifierProvider<NotificationsProvider>.value(
        value: notificationsProvider ??
            MockNotificationsProviderForTickets(apiClient, []),
      ),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
      ),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(),
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
      theme: quickDeliveryTheme,
      home: home,
    ),
  );
}

void main() {
  late ApiClient apiClient;
  late UserProfile testCustomer;
  late MockAuthProviderForTest authProvider;

  setUp(() {
    apiClient = ApiClient();
    testCustomer = UserProfile(
      id: 'cust-101',
      email: 'customer@example.com',
      username: 'AliceCustomer',
      role: 'user',
    );
    authProvider = MockAuthProviderForTest(apiClient, mockUser: testCustomer);
  });

  group('CustomerTicketsScreen', () {
    testWidgets('renders ticket list with status badges and details',
        (WidgetTester tester) async {
      final tickets = [
        SupportTicket(
          id: 'TICKET-001',
          customerId: 'cust-101',
          subject: 'Damaged package delivery',
          status: 'open',
          contextId: 'JOB-999',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        SupportTicket(
          id: 'TICKET-002',
          customerId: 'cust-101',
          subject: 'Late food order',
          status: 'resolved',
          resolutionNote: 'Refund credited to customer wallet',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ];

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockTickets: tickets,
      );

      await tester.pumpWidget(buildTestApp(
        home: const CustomerTicketsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      // Verify header / title
      expect(find.text('Support Tickets'), findsOneWidget);

      // Verify tickets rendered
      expect(find.text('Ticket #TICKET-001'), findsOneWidget);
      expect(find.text('Damaged package delivery'), findsOneWidget);
      expect(find.text('Ticket #TICKET-002'), findsOneWidget);
      expect(find.text('Late food order'), findsOneWidget);

      // Verify resolution note preview on resolved ticket
      expect(
        find.text('Refund credited to customer wallet'),
        findsOneWidget,
      );

      // Status badges
      expect(find.byType(StatusBadge), findsNWidgets(2));
    });

    testWidgets('filters tickets correctly by All, Open, and Resolved pills',
        (WidgetTester tester) async {
      final tickets = [
        SupportTicket(
          id: 'TICKET-OPEN',
          customerId: 'cust-101',
          subject: 'Unresolved issue',
          status: 'pending',
          createdAt: DateTime.now(),
        ),
        SupportTicket(
          id: 'TICKET-RESOLVED',
          customerId: 'cust-101',
          subject: 'Already fixed issue',
          status: 'resolved',
          resolutionNote: 'Resolved by support agent',
          createdAt: DateTime.now(),
        ),
      ];

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockTickets: tickets,
      );

      await tester.pumpWidget(buildTestApp(
        home: const CustomerTicketsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      // Initial state: 'All' selected -> both visible
      expect(find.text('Ticket #TICKET-OPEN'), findsOneWidget);
      expect(find.text('Ticket #TICKET-RESOLVED'), findsOneWidget);

      // Tap 'Open' filter
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Ticket #TICKET-OPEN'), findsOneWidget);
      expect(find.text('Ticket #TICKET-RESOLVED'), findsNothing);

      // Tap 'Resolved' filter
      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();

      expect(find.text('Ticket #TICKET-OPEN'), findsNothing);
      expect(find.text('Ticket #TICKET-RESOLVED'), findsOneWidget);

      // Tap 'All' again
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(find.text('Ticket #TICKET-OPEN'), findsOneWidget);
      expect(find.text('Ticket #TICKET-RESOLVED'), findsOneWidget);
    });

    testWidgets('shows empty state when no tickets match',
        (WidgetTester tester) async {
      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockTickets: [],
      );

      await tester.pumpWidget(buildTestApp(
        home: const CustomerTicketsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No support tickets yet'), findsOneWidget);
      expect(find.text('Open New Ticket'), findsOneWidget);
    });

    testWidgets('FAB opens CreateTicketDialog', (WidgetTester tester) async {
      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockTickets: [],
      );

      await tester.pumpWidget(buildTestApp(
        home: const CustomerTicketsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      final fab = find.byKey(const Key('create_ticket_fab'));
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(find.byType(CreateTicketDialog), findsOneWidget);
    });

    testWidgets('tapping ticket card navigates to TicketChatScreen',
        (WidgetTester tester) async {
      final ticket = SupportTicket(
        id: 'TICKET-NAV',
        customerId: 'cust-101',
        subject: 'Navigation test issue',
        status: 'in_progress',
        createdAt: DateTime.now(),
      );

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockTickets: [ticket],
      );

      await tester.pumpWidget(buildTestApp(
        home: const CustomerTicketsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      final ticketCard = find.byKey(const Key('ticket_card_TICKET-NAV'));
      expect(ticketCard, findsOneWidget);
      await tester.tap(ticketCard);
      await tester.pumpAndSettle();

      expect(find.byType(TicketChatScreen), findsOneWidget);
      expect(chatProvider.lastSubscribedChannel, equals('ticket:TICKET-NAV'));
    });
  });

  group('TicketChatScreen', () {
    testWidgets('subscribes to ticket channel and renders messages',
        (WidgetTester tester) async {
      final ticket = SupportTicket(
        id: 'TICKET-CHAT-1',
        customerId: 'cust-101',
        subject: 'Wrong item received',
        status: 'in_progress',
        createdAt: DateTime.now(),
      );

      final messages = [
        ChatMessage(
          channel: 'ticket:TICKET-CHAT-1',
          senderId: 'cust-101',
          senderUsername: 'AliceCustomer',
          content: 'Hello, I received the wrong item in my order.',
          type: 'chat',
        ),
        ChatMessage(
          channel: 'ticket:TICKET-CHAT-1',
          senderId: 'agent-42',
          senderUsername: 'Agent Support',
          content: 'We are checking with the courier right now.',
          type: 'chat',
        ),
      ];

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockMessages: messages,
      );

      await tester.pumpWidget(buildTestApp(
        home: TicketChatScreen(ticket: ticket),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      // Channel subscribed
      expect(
        chatProvider.lastSubscribedChannel,
        equals('ticket:TICKET-CHAT-1'),
      );

      // Messages rendered
      expect(
        find.text('Hello, I received the wrong item in my order.'),
        findsOneWidget,
      );
      expect(
        find.text('We are checking with the courier right now.'),
        findsOneWidget,
      );

      // Open ticket has input field and send button
      expect(find.byKey(const Key('ticket_chat_input_field')), findsOneWidget);
      expect(
        find.byKey(const Key('ticket_chat_send_button')),
        findsOneWidget,
      );
    });

    testWidgets('sends message via chatProvider when open',
        (WidgetTester tester) async {
      final ticket = SupportTicket(
        id: 'TICKET-SEND',
        customerId: 'cust-101',
        subject: 'Chat sending test',
        status: 'open',
        createdAt: DateTime.now(),
      );

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockMessages: [],
      );

      await tester.pumpWidget(buildTestApp(
        home: TicketChatScreen(ticket: ticket),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      final input = find.byKey(const Key('ticket_chat_input_field'));
      final sendBtn = find.byKey(const Key('ticket_chat_send_button'));

      await tester.enterText(input, 'Can someone please help me?');
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(
        chatProvider.lastMessageSent,
        equals('Can someone please help me?'),
      );
      expect(find.text('Can someone please help me?'), findsOneWidget);
    });

    testWidgets('resolved ticket displays resolution banner and disables input',
        (WidgetTester tester) async {
      final ticket = SupportTicket(
        id: 'TICKET-CLOSED',
        customerId: 'cust-101',
        subject: 'Completed ticket',
        status: 'resolved',
        resolutionNote: 'Replacement was dispatched successfully',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockMessages: [],
      );

      await tester.pumpWidget(buildTestApp(
        home: TicketChatScreen(ticket: ticket),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      // Prominent banner
      expect(find.text('Ticket Resolved'), findsOneWidget);
      expect(
        find.text('Resolution Note: Replacement was dispatched successfully'),
        findsOneWidget,
      );

      // Closed input bar
      expect(
        find.text('This ticket is resolved and closed for new messages.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_chat_input_field')), findsNothing);
      expect(find.byKey(const Key('ticket_chat_send_button')), findsNothing);
    });

    testWidgets(
        'transitions dynamically to resolved when ticket_resolution message arrives',
        (WidgetTester tester) async {
      final ticket = SupportTicket(
        id: 'TICKET-DYNAMIC',
        customerId: 'cust-101',
        subject: 'Dynamic resolution test',
        status: 'in_progress',
        createdAt: DateTime.now(),
      );

      final chatProvider = MockChatProviderForTest(
        apiClient,
        mockMessages: [
          ChatMessage(
            channel: 'ticket:TICKET-DYNAMIC',
            senderId: 'cust-101',
            senderUsername: 'AliceCustomer',
            content: 'Please look into this.',
            type: 'chat',
          ),
        ],
      );

      await tester.pumpWidget(buildTestApp(
        home: TicketChatScreen(ticket: ticket),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      // Initially open
      expect(find.byKey(const Key('ticket_chat_input_field')), findsOneWidget);
      expect(find.text('Ticket Resolved'), findsNothing);

      // Simulate arrival of ticket_resolution message
      chatProvider.addMessage(ChatMessage(
        channel: 'ticket:TICKET-DYNAMIC',
        senderId: 'system',
        senderUsername: 'System',
        content: 'Issue resolved: refund processed',
        type: 'ticket_resolution',
      ));
      await tester.pumpAndSettle();

      // Now resolved banner and closed input should be displayed
      expect(find.text('Ticket Resolved'), findsOneWidget);
      expect(
        find.text('Resolution Note: Issue resolved: refund processed'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket_chat_input_field')), findsNothing);
    });
  });

  group('SettingsScreen and Notifications Integration', () {
    testWidgets('SettingsScreen has Support Tickets row navigating to screen',
        (WidgetTester tester) async {
      final chatProvider = MockChatProviderForTest(apiClient);

      await tester.pumpWidget(buildTestApp(
        home: const SettingsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
      ));
      await tester.pumpAndSettle();

      final ticketsRow = find.byKey(const Key('support_tickets_setting_row'));
      expect(ticketsRow, findsOneWidget);
      await tester.ensureVisible(ticketsRow);
      await tester.tap(ticketsRow);
      await tester.pumpAndSettle();

      expect(find.byType(CustomerTicketsScreen), findsOneWidget);
    });

    testWidgets('NotificationsScreen ticket_resolved notification card tap',
        (WidgetTester tester) async {
      final notif = NotificationModel(
        id: 'n-ticket-1',
        tenantId: 'tenant-1',
        title: 'Support Ticket Update',
        body: 'Ticket TICKET-ABC-123 resolved: Full refund processed',
        type: 'ticket_resolved',
        isRead: false,
        timestamp: DateTime.now(),
      );

      final notifsProvider = MockNotificationsProviderForTickets(
        apiClient,
        [notif],
      );
      final chatProvider = MockChatProviderForTest(apiClient);

      await tester.pumpWidget(buildTestApp(
        home: const NotificationsScreen(),
        authProvider: authProvider,
        chatProvider: chatProvider,
        notificationsProvider: notifsProvider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Support Ticket Update'), findsOneWidget);

      // Tap card
      await tester.tap(find.text('Support Ticket Update'));
      await tester.pumpAndSettle();

      // Successfully navigated to TicketChatScreen
      expect(find.byType(TicketChatScreen), findsOneWidget);
      expect(
          chatProvider.lastSubscribedChannel, equals('ticket:TICKET-ABC-123'));
    });
  });
}
