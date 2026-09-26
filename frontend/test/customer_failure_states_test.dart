import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/support_ticket.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/rating_screen.dart';
import 'package:frontend/screens/ticket_chat_screen.dart';
import 'package:frontend/widgets/themed_error_banner.dart';
import 'package:frontend/widgets/themed_loading_indicator.dart';

// Step-1 coverage for audit findings C2–C7 (UI_UX_AUDIT_2026-09.md),
// reusing UX_PATTERNS.md Rule 1 (persistent inline banner + retry).
// Every test below proves the failure renders DIFFERENTLY from the
// legitimate loading/empty/waiting state — not just "banner appears":
// the old misleading state (empty placeholder / "waiting" copy /
// "no ratings" label with zero error signal) is asserted absent in the
// failure render, or the banner/no-banner contrast across the two
// renders is asserted explicitly.

class _StubAuthProvider extends AuthProvider {
  final UserProfile? _stubUser;
  final String? _stubToken;

  _StubAuthProvider(
    super.apiClient, {
    UserProfile? stubUser,
    String? stubToken,
  })  : _stubUser = stubUser,
        _stubToken = stubToken;

  @override
  UserProfile? get user => _stubUser;

  @override
  String? get token => _stubToken;
}

/// Real ChatProvider fetch/send paths, but connection setup torn out so
/// no real WebSocket is ever opened in tests.
class _HarnessedChatProvider extends ChatProvider {
  int sendCalls = 0;
  bool failSend = false;

  _HarnessedChatProvider(super.apiClient);

  @override
  void connectAndSubscribeChannel(String channel, String token) {}

  @override
  void connectAndSubscribe(String jobId, String token) {}

  @override
  void disconnect() {}

  @override
  Future<void> sendMessage(String content) async {
    if (failSend) {
      sendCalls++;
      throw Exception('WebSocket is not connected');
    }
    return super.sendMessage(content);
  }
}

class _StubApiClient extends ApiClient {
  _StubApiClient() : super(baseUrl: 'http://localhost:3002');

  /// When set, GET /chat/history waits on this gate (C2/C3 loading tests).
  Completer<List<dynamic>>? historyGate;

  /// 'ok' returns [], 'empty' returns [], 'fail' throws 500.
  String historyMode = 'ok';
  int historyCalls = 0;

  /// 'ok' returns a rated summary; 'zero' returns count 0; 'fail' throws.
  String ratingsMode = 'ok';
  int ratingsCalls = 0;

  @override
  Future<dynamic> get(String path,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    if (path == '/chat/history') {
      historyCalls++;
      if (historyGate != null) {
        return historyGate!.future;
      }
      if (historyMode == 'fail') {
        throw ApiClientException('history fetch failed', statusCode: 500);
      }
      return <dynamic>[];
    }
    if (path == '/users/ratings') {
      ratingsCalls++;
      if (ratingsMode == 'fail') {
        throw ApiClientException('ratings fetch failed', statusCode: 500);
      }
      if (ratingsMode == 'zero') {
        return {'average_rating': 0.0, 'count': 0, 'ratings': []};
      }
      return {'average_rating': 4.5, 'count': 12, 'ratings': []};
    }
    return {'status': 'ok'};
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    return {'status': 'ok'};
  }
}

Widget _testApp({
  required Widget home,
  required AuthProvider auth,
  ChatProvider? chat,
  MarketplaceProvider? marketplace,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      if (chat != null) ChangeNotifierProvider<ChatProvider>.value(value: chat),
      if (marketplace != null)
        ChangeNotifierProvider<MarketplaceProvider>.value(value: marketplace),
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

SupportTicket _ticketFixture() => SupportTicket(
      id: 'TICKET-C2-1',
      customerId: 'cust-101',
      subject: 'Where is my order',
      status: 'in_progress',
      createdAt: DateTime.now(),
    );

UserProfile _customerFixture() => UserProfile(
      id: 'cust-1',
      email: 'cust@test.com',
      username: 'cust',
      role: 'user',
    );

Job _jobFixture() => Job(
      id: 'job-r1',
      ownerId: 'owner-1',
      employeeId: 'emp-9',
      userId: 'cust-1',
      serviceId: 'svc-1',
      status: 'completed',
      location: JobLocation(latitude: 30.0, longitude: 31.0),
      paymentMethod: 'cod',
    );

void _mobileViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('C2 ticket history loading state', () {
    testWidgets(
        'loader shows during fetch; empty placeholder only after success-empty',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.historyGate = Completer<List<dynamic>>();
      final auth = _StubAuthProvider(ApiClient(),
          stubUser: _customerFixture(), stubToken: 'tok');
      final chat = _HarnessedChatProvider(api);
      await tester.pumpWidget(_testApp(
        home: TicketChatScreen(ticket: _ticketFixture()),
        auth: auth,
        chat: chat,
      ));
      // Post-frame fetch starts and hits the held gate.
      await tester.pump();
      await tester.pump();

      // Loading render: indicator present, empty-conversation icon absent
      // (previously the placeholder flashed here — the C2 defect).
      expect(find.byType(ThemedLoadingIndicator), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

      // Release with a genuinely empty history: loader gone, placeholder
      // present, and no error banner anywhere.
      api.historyGate!.complete(<dynamic>[]);
      await tester.pumpAndSettle();

      expect(find.byType(ThemedLoadingIndicator), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byType(ThemedErrorBanner), findsNothing);
    });
  });

  group('C3 job-chat history loading state', () {
    testWidgets(
        'loader shows during fetch; empty state reserved for empty thread',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.historyGate = Completer<List<dynamic>>();
      final auth = _StubAuthProvider(ApiClient(),
          stubUser: _customerFixture(), stubToken: 'tok');
      final chat = _HarnessedChatProvider(api);
      await tester.pumpWidget(_testApp(
        home: const ChatScreen(jobId: 'job-1'),
        auth: auth,
        chat: chat,
      ));
      await tester.pump();
      await tester.pump();

      // During history fetch isConnecting is still false, so only the new
      // isLoadingHistory arm can show the loader (previously the empty
      // state flashed here — the C3 defect).
      expect(find.byType(ThemedLoadingIndicator), findsOneWidget);
      expect(find.byIcon(Icons.chat_outlined), findsNothing);

      api.historyGate!.complete(<dynamic>[]);
      await tester.pumpAndSettle();

      expect(find.byType(ThemedLoadingIndicator), findsNothing);
      expect(find.byIcon(Icons.chat_outlined), findsOneWidget);
    });
  });

  group('C4 ticket history failure banner', () {
    testWidgets('failed fetch shows retryable banner; retry success clears it',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.historyMode = 'fail';
      final auth = _StubAuthProvider(ApiClient(),
          stubUser: _customerFixture(), stubToken: 'tok');
      final chat = _HarnessedChatProvider(api);
      await tester.pumpWidget(_testApp(
        home: TicketChatScreen(ticket: _ticketFixture()),
        auth: auth,
        chat: chat,
      ));
      await tester.pumpAndSettle();

      // Failure render carries the Rule-1 banner (previously: empty
      // placeholder with zero signal — the C4 defect). The 500 maps to
      // the friendly server-error copy via friendlyErrorMessage.
      expect(find.byType(ThemedErrorBanner), findsOneWidget);
      expect(
          find.text(
              'Something went wrong on our end. Please try again shortly.'),
          findsOneWidget);

      // Retry re-fires the fetch; flip the mock healthy first.
      api.historyMode = 'ok';
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.historyCalls, 2);
      expect(find.byType(ThemedErrorBanner), findsNothing);
      // ...while the same empty placeholder now renders banner-free: the
      // banner/no-banner contrast is what distinguishes failure from
      // legitimate empty.
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });
  });

  group('C5 per-card ratings failure', () {
    testWidgets(
        'failed fetch shows retry affordance instead of "no ratings" label',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.ratingsMode = 'fail';
      final marketplace = MarketplaceProvider(api);
      await tester.pumpWidget(_testApp(
        home: const Scaffold(
          body: ServiceRatingWidget(tenantId: 'tenant-1'),
        ),
        auth: _StubAuthProvider(ApiClient()),
        marketplace: marketplace,
      ));
      await tester.pumpAndSettle();

      // Failure render: the misleading "no ratings" label is absent...
      expect(find.text('No ratings'), findsNothing);
      // ...and a compact retry affordance stands in its place.
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Retry against a healthy backend renders the real star row.
      api.ratingsMode = 'ok';
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      expect(api.ratingsCalls, 2);
      expect(find.byIcon(Icons.refresh), findsNothing);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text('4.5 (12)'), findsOneWidget);
    });

    testWidgets('genuine zero count still renders the "no ratings" label',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.ratingsMode = 'zero';
      final marketplace = MarketplaceProvider(api);
      await tester.pumpWidget(_testApp(
        home: const Scaffold(
          body: ServiceRatingWidget(tenantId: 'tenant-1'),
        ),
        auth: _StubAuthProvider(ApiClient()),
        marketplace: marketplace,
      ));
      await tester.pumpAndSettle();

      // Legitimate empty keeps the label and shows no retry affordance:
      // the label/retry contrast is what distinguishes zero from failure.
      expect(find.text('No ratings'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });
  });

  group('C6 rating status-check failure', () {
    testWidgets(
        'failed check shows error banner instead of "waiting" visualizer',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      api.ratingsMode = 'fail';
      final auth = _StubAuthProvider(ApiClient(),
          stubUser: _customerFixture(), stubToken: 'tok');
      final marketplace = MarketplaceProvider(api);
      _mobileViewport(tester);
      await tester.pumpWidget(_testApp(
        home: RatingScreen(job: _jobFixture()),
        auth: auth,
        marketplace: marketplace,
      ));
      await tester.pumpAndSettle();

      // Failure render: inline retryable notice present...
      expect(
          find.byKey(const Key('rating_status_error_banner')), findsOneWidget);
      // ...while the misleading "waiting for other party" copy is absent
      // (previously it rendered here on network failure — the C6 defect).
      expect(find.text('Waiting for other party...'), findsNothing);

      // The AppBar refresh doubles as retry: flip healthy, tap, and the
      // banner yields to the genuine waiting state.
      api.ratingsMode = 'ok';
      await tester.tap(find.byTooltip('Refresh Status'));
      await tester.pumpAndSettle();

      expect(api.ratingsCalls, 2);
      expect(find.byKey(const Key('rating_status_error_banner')), findsNothing);
      expect(find.text('Waiting for other party...'), findsOneWidget);
    });
  });

  group('C7 ticket send retry parity', () {
    testWidgets('send failure keeps text and offers one-tap resend',
        (WidgetTester tester) async {
      final api = _StubApiClient();
      final auth = _StubAuthProvider(ApiClient(),
          stubUser: _customerFixture(), stubToken: 'tok');
      final chat = _HarnessedChatProvider(api)..failSend = true;
      await tester.pumpWidget(_testApp(
        home: TicketChatScreen(ticket: _ticketFixture()),
        auth: auth,
        chat: chat,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('ticket_chat_input_field')), 'hello ticket');
      await tester.tap(find.byKey(const Key('ticket_chat_send_button')));
      await tester.pumpAndSettle();

      expect(chat.sendCalls, 1);
      // Typed text is preserved for the retry (not cleared on failure).
      expect(find.widgetWithText(TextField, 'hello ticket'), findsOneWidget);
      // Parity with chat_screen: the failure snackbar carries a RETRY
      // action (previously absent — the C7 defect).
      expect(find.text('RETRY'), findsOneWidget);

      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(chat.sendCalls, 2);
    });
  });
}
