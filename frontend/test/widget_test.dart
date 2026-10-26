import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/user_profile.dart';

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
  // UX-17: with the restore splash live on the first frame, the AuthProvider
  // secure-storage read must actually complete in tests or the gate stays on
  // the splash forever. Register the plugin mock so the read returns null
  // (no stored session) quickly, as app starts do.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('App renders login screen', (WidgetTester tester) async {
    final apiClient = ApiClient();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
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

    // UX-17: the gate shows the neutral splash while AuthProvider is
    // restoring the stored session; settle it before asserting login chrome.
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    // The sign-in page with its pre-login toggles.
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(const Key('login_theme')), findsOneWidget);
    expect(find.byKey(const Key('login_language')), findsOneWidget);
  });

  testWidgets('Pre-login theme and language toggles invoke shared providers',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
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

    // UX-17: settle the restore splash before asserting pre-login chrome.
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    // Initial theme mode is system
    expect(themeProvider.themeMode, ThemeMode.system);

    // Tap theme toggle button -> switches to light mode
    await tester.tap(find.byKey(const Key('login_theme')));
    await tester.pump();
    expect(themeProvider.themeMode, ThemeMode.light);

    // Tap theme toggle button -> switches to dark mode
    await tester.tap(find.byKey(const Key('login_theme')));
    await tester.pump();
    expect(themeProvider.themeMode, ThemeMode.dark);

    // Tap language toggle button -> switches to Arabic
    await tester.tap(find.byKey(const Key('login_language')));
    await tester.pump();
    expect(localeProvider.locale?.languageCode, 'ar');
  });
}
