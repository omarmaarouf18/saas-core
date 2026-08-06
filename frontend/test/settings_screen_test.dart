import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/widgets/create_ticket_dialog.dart';
import 'package:frontend/screens/settings_screen.dart';
import 'package:frontend/screens/login_screen.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> storage = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return storage[key];
  }
}

class MockAuthProvider extends AuthProvider {
  final UserProfile? _mockUser;
  bool logoutCalled = false;

  MockAuthProvider(super.apiClient, this._mockUser);

  @override
  UserProfile? get user => _mockUser;

  @override
  String? get token => "mock-token";

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

void main() {
  late ApiClient apiClient;

  setUp(() {
    apiClient = ApiClient();
  });

  Widget buildSettingsApp({
    required AuthProvider authProvider,
    required ThemeProvider themeProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(apiClient),
        ),
      ],
      child: MaterialApp(
        themeMode: themeProvider.themeMode,
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets(
      '(a) Theme selector updates ThemeProvider state and persists to storage',
      (WidgetTester tester) async {
    final fakeStorage = FakeSecureStorage();
    final themeProvider = ThemeProvider(storage: fakeStorage);
    final mockUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner1',
      role: 'owner',
    );
    final authProvider = MockAuthProvider(apiClient, mockUser);

    await tester.pumpWidget(buildSettingsApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(themeProvider.themeMode, ThemeMode.system);

    // Tap Light Mode button
    final lightBtn = find.byKey(const Key('theme_light_button'));
    expect(lightBtn, findsOneWidget);
    await tester.tap(lightBtn);
    await tester.pumpAndSettle();

    expect(themeProvider.themeMode, ThemeMode.light);
    expect(fakeStorage.storage['theme_mode'], 'light');

    // Tap Dark Mode button
    final darkBtn = find.byKey(const Key('theme_dark_button'));
    expect(darkBtn, findsOneWidget);
    await tester.tap(darkBtn);
    await tester.pumpAndSettle();

    expect(themeProvider.themeMode, ThemeMode.dark);
    expect(fakeStorage.storage['theme_mode'], 'dark');
  });

  testWidgets('(b1) Language row renders with Coming Soon badge',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner_user',
      role: 'owner',
    );
    final authProvider = MockAuthProvider(apiClient, ownerUser);

    await tester.pumpWidget(buildSettingsApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    // Verify "Coming Soon" badge exists for placeholder row (Language)
    expect(find.text("Coming Soon"), findsOneWidget);
  });

  testWidgets('(b2) Tapping Language row displays feedback snackbar',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner_user',
      role: 'owner',
    );
    final authProvider = MockAuthProvider(apiClient, ownerUser);

    await tester.pumpWidget(buildSettingsApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    final langRow = find.byKey(const Key('language_setting_row'));
    expect(langRow, findsOneWidget);
    await tester.ensureVisible(langRow);
    await tester.tap(langRow);
    await tester.pump();
    expect(find.text("Language selection is coming soon"), findsOneWidget);
  });

  testWidgets('(b3) Tapping Customer Service row opens CreateTicketDialog',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner_user',
      role: 'owner',
    );
    final authProvider = MockAuthProvider(apiClient, ownerUser);

    await tester.pumpWidget(buildSettingsApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    final csRow = find.byKey(const Key('customer_service_setting_row'));
    expect(csRow, findsOneWidget);
    await tester.ensureVisible(csRow);
    await tester.tap(csRow);
    await tester.pumpAndSettle();

    expect(find.byType(CreateTicketDialog), findsOneWidget);
    expect(find.text("Open Complaint Ticket"), findsOneWidget);
  });

  testWidgets(
      '(c) Role-based visibility: owner sees Owner Configuration, user sees My Account, employee sees neither',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());

    // 1. Owner role check
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner_user',
      role: 'owner',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, ownerUser),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner_config_setting_row')), findsOneWidget);
    expect(find.byKey(const Key('my_account_setting_row')), findsNothing);

    // 2. Customer ('user') role check
    final customerUser = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'cust_user',
      role: 'user',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, customerUser),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner_config_setting_row')), findsNothing);
    expect(find.byKey(const Key('my_account_setting_row')), findsOneWidget);

    // 3. Employee role check
    final employeeUser = UserProfile(
      id: 'emp-1',
      email: 'emp@example.com',
      username: 'emp_user',
      role: 'employee',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, employeeUser),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('owner_config_setting_row')), findsNothing);
    expect(find.byKey(const Key('my_account_setting_row')), findsNothing);
  });

  testWidgets(
      '(d) Tapping Logout calls auth.logout and navigates to LoginScreen',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final user = UserProfile(
      id: 'user-1',
      email: 'user@example.com',
      username: 'test_user',
      role: 'user',
    );
    final mockAuth = MockAuthProvider(apiClient, user);

    await tester.pumpWidget(buildSettingsApp(
      authProvider: mockAuth,
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    final logoutBtn = find.byKey(const Key('settings_logout_button'));
    expect(logoutBtn, findsOneWidget);

    await tester.ensureVisible(logoutBtn);
    await tester.pumpAndSettle();
    await tester.tap(logoutBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(mockAuth.logoutCalled, isTrue);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
