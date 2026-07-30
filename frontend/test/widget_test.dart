import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/screens/signup_screen.dart';
import 'package:frontend/screens/chat_screen.dart';

class MockAuthProvider extends AuthProvider {
  final UserProfile? mockUser;
  MockAuthProvider(super.apiClient, this.mockUser);

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => "mock-token";
}

class MockChatProvider extends ChatProvider {
  final List<ChatMessage> mockMessages;
  MockChatProvider(super.apiClient, this.mockMessages);

  @override
  List<ChatMessage> get messages => mockMessages;

  @override
  Future<void> fetchHistory(String jobId, String token) async {
    // No-op to avoid network calls
  }

  @override
  void connectAndSubscribe(String jobId, String token) {
    // No-op to avoid WebSocket calls
  }

  @override
  bool get isConnected => true;
}

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
          ChangeNotifierProvider(create: (_) => OwnerProvider(apiClient)),
          ChangeNotifierProvider(
              create: (_) => EmployeeJobsProvider(apiClient)),
          ChangeNotifierProvider(
              create: (_) => NotificationsProvider(apiClient)),
        ],
        child: const MyApp(),
      ),
    );

    // Verify that the login screen elements render correctly.
    expect(find.text('Quick Delivery'), findsOneWidget);
    expect(find.text('Log in to manage your services'), findsOneWidget);
  });

  testWidgets('OtpScreen OTP length regression guard',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = AuthProvider(apiClient);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: OtpScreen(email: 'test@example.com'),
        ),
      ),
    );

    // 1. Assert the TextFormField's maxLength property is exactly 6
    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.maxLength, 6);

    // 2. Validate the validator function logic
    final textFormFieldFinder = find.byType(TextFormField);
    expect(textFormFieldFinder, findsOneWidget);

    final textFormField = tester.widget<TextFormField>(textFormFieldFinder);
    final validator = textFormField.validator!;

    // Test a 5-digit string -> error message
    expect(validator('12345'), 'OTP must be exactly 6 digits');

    // Test a 4-digit string -> error message
    expect(validator('1234'), 'OTP must be exactly 6 digits');

    // Test a valid 6-digit string -> null (no error)
    expect(validator('123456'), isNull);
  });

  testWidgets('SignupScreen Username validation test',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = AuthProvider(apiClient);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: SignupScreen(),
        ),
      ),
    );

    final textFormFields =
        tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(textFormFields.length, 3); // username, email, password

    final usernameField = textFormFields.first;
    final validator = usernameField.validator!;

    // Test cases:
    // 1. Missing username
    expect(validator(''), 'Please enter a username');
    expect(validator(null), 'Please enter a username');

    // 2. Too short username (under 3 runes)
    expect(validator('ab'), 'Username must be at least 3 characters');

    // 3. Too long username (over 30 runes)
    expect(validator('a' * 31), 'Username must be at most 30 characters');

    // 4. Invalid character rejection
    expect(validator('user\$'), 'Username contains invalid characters');
    expect(validator('user@123'), 'Username contains invalid characters');

    // 5. Valid Arabic username success
    expect(validator('عمر_معروف'), isNull);

    // 6. Valid mixed Latin/Arabic/space/digits/underscore success
    expect(validator('Omar معروف_123'), isNull);
  });

  testWidgets('ChatScreen renders sender_username instead of sender_id',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final authProvider = MockAuthProvider(
      apiClient,
      UserProfile(
        id: 'me-123',
        email: 'me@example.com',
        username: 'my_username',
        role: 'user',
      ),
    );

    final mockMessages = [
      ChatMessage(
        channel: 'job:job-123',
        senderId: 'other-456',
        senderUsername: 'FriendlyArabic_عمر',
        content: 'Hello, this is a test message!',
        type: 'message',
      ),
      ChatMessage(
        channel: 'job:job-123',
        senderId: 'agent-789',
        senderUsername: 'Agent Support-99',
        content: 'System support message',
        type: 'message',
      ),
    ];

    final chatProvider = MockChatProvider(apiClient, mockMessages);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ],
        child: const MaterialApp(
          home: ChatScreen(jobId: 'job-123'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Hello, this is a test message!'), findsOneWidget);
    expect(find.text('System support message'), findsOneWidget);

    expect(find.text('FriendlyArabic_عمر'), findsOneWidget);
    expect(find.text('Agent Support-99'), findsOneWidget);

    expect(find.textContaining('other-456'), findsNothing);
    expect(find.textContaining('agent-789'), findsNothing);
  });
}
