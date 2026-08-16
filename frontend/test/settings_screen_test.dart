import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
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
    LocaleProvider? localeProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<LocaleProvider>(
            create: (_) => localeProvider ?? LocaleProvider()),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(apiClient),
        ),
      ],
      child: MaterialApp(
        theme: quickDeliveryTheme,
        darkTheme: quickDeliveryDarkTheme,
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

  testWidgets('(b1) Language selector renders SegmentedButton with options',
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

    expect(find.byKey(const Key('language_selector')), findsOneWidget);
    expect(find.byKey(const Key('lang_auto_button')), findsOneWidget);
    expect(find.byKey(const Key('lang_en_button')), findsOneWidget);
    expect(find.byKey(const Key('lang_ar_button')), findsOneWidget);
  });

  testWidgets('(b2) Tapping Language options switches locale in LocaleProvider',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final localeProvider = LocaleProvider();
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
      localeProvider: localeProvider,
    ));
    await tester.pumpAndSettle();

    final arBtn = find.byKey(const Key('lang_ar_button'));
    expect(arBtn, findsOneWidget);
    await tester.tap(arBtn);
    await tester.pumpAndSettle();

    expect(localeProvider.locale?.languageCode, 'ar');
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

  testWidgets(
      '(e) KYC verification entry point visibility logic: customer role hides row, unverified owner/employee shows row, approved hides row',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());

    // 1. Unverified customer ('user' role) -> hides KYC row
    final unverifiedCustomer = UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      username: 'customer1',
      role: 'user',
      kycStatus: 'unverified',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, unverifiedCustomer),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyc_verification_setting_row')), findsNothing);

    // 2. Unverified owner ('owner' role) -> shows KYC row
    final unverifiedOwner = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner1',
      role: 'owner',
      kycStatus: 'unverified',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, unverifiedOwner),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('kyc_verification_setting_row')), findsOneWidget);

    // 3. Unverified employee ('employee' role) -> shows KYC row
    final unverifiedEmployee = UserProfile(
      id: 'emp-1',
      email: 'emp@example.com',
      username: 'emp1',
      role: 'employee',
      kycStatus: 'unverified',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, unverifiedEmployee),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('kyc_verification_setting_row')), findsOneWidget);

    // 4. Approved owner -> hides KYC row
    final approvedOwner = UserProfile(
      id: 'owner-2',
      email: 'approved_owner@example.com',
      username: 'approved_owner',
      role: 'owner',
      kycStatus: 'approved',
    );
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, approvedOwner),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('kyc_verification_setting_row')), findsNothing);
  });

  testWidgets(
      '(f) SegmentedButton explicit style, contrast, font size, and bold weight verification in Light and Dark mode',
      (WidgetTester tester) async {
    final themeProvider = ThemeProvider(storage: FakeSecureStorage());
    final ownerUser = UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'owner1',
      role: 'owner',
    );

    // 1. Test Light Mode Contrast & Style
    themeProvider.setThemeMode(ThemeMode.light);
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, ownerUser),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    final themeSelectorFinder = find.byKey(const Key('theme_mode_selector'));
    expect(themeSelectorFinder, findsOneWidget);
    final SegmentedButton<ThemeMode> lightThemeSelector =
        tester.widget(themeSelectorFinder);
    final lightStyle = lightThemeSelector.style ??
        Theme.of(tester.element(themeSelectorFinder))
            .segmentedButtonTheme
            .style!;

    final lightTextStyle =
        lightStyle.textStyle?.resolve({WidgetState.selected});
    expect(lightTextStyle?.fontSize, 12.0);
    expect(lightTextStyle?.fontWeight, FontWeight.bold);

    // Light mode unselected and selected foreground & background colors
    final lightUnselectedBg =
        lightStyle.backgroundColor?.resolve({WidgetState.focused});
    final lightUnselectedFg =
        lightStyle.foregroundColor?.resolve({WidgetState.focused});
    final lightSelectedBg =
        lightStyle.backgroundColor?.resolve({WidgetState.selected});
    final lightSelectedFg =
        lightStyle.foregroundColor?.resolve({WidgetState.selected});

    expect(lightUnselectedFg, isNotNull);
    expect(lightUnselectedBg, isNotNull);
    expect(lightSelectedFg, isNotNull);
    expect(lightSelectedBg, isNotNull);

    // Assert high contrast between unselected text and unselected background
    // Calculate luminance & contrast ratio: (L1 + 0.05) / (L2 + 0.05)
    double contrastRatio(Color c1, Color c2) {
      final lum1 = c1.computeLuminance();
      final lum2 = c2.computeLuminance();
      final brightest = lum1 > lum2 ? lum1 : lum2;
      final darkest = lum1 > lum2 ? lum2 : lum1;
      return (brightest + 0.05) / (darkest + 0.05);
    }

    final lightUnselectedRatio =
        contrastRatio(lightUnselectedFg!, lightUnselectedBg!);
    final lightSelectedRatio =
        contrastRatio(lightSelectedFg!, lightSelectedBg!);

    // WCAG AA requires >= 4.5:1 for normal text
    expect(lightUnselectedRatio, greaterThanOrEqualTo(4.5));
    expect(lightSelectedRatio, greaterThanOrEqualTo(4.5));

    // 2. Test Dark Mode Contrast & Style
    themeProvider.setThemeMode(ThemeMode.dark);
    await tester.pumpWidget(buildSettingsApp(
      authProvider: MockAuthProvider(apiClient, ownerUser),
      themeProvider: themeProvider,
    ));
    await tester.pumpAndSettle();

    final darkThemeSelector = tester.widget<SegmentedButton<ThemeMode>>(
        find.byKey(const Key('theme_mode_selector')));
    final darkStyle = darkThemeSelector.style ??
        Theme.of(tester.element(find.byKey(const Key('theme_mode_selector'))))
            .segmentedButtonTheme
            .style!;
    final darkTextStyle = darkStyle.textStyle?.resolve({WidgetState.selected});
    expect(darkTextStyle?.fontSize, 12.0);
    expect(darkTextStyle?.fontWeight, FontWeight.bold);

    final darkUnselectedBg =
        darkStyle.backgroundColor?.resolve({WidgetState.focused});
    final darkUnselectedFg =
        darkStyle.foregroundColor?.resolve({WidgetState.focused});
    final darkSelectedBg =
        darkStyle.backgroundColor?.resolve({WidgetState.selected});
    final darkSelectedFg =
        darkStyle.foregroundColor?.resolve({WidgetState.selected});

    expect(darkUnselectedFg, isNotNull);
    expect(darkUnselectedBg, isNotNull);
    expect(darkSelectedFg, isNotNull);
    expect(darkSelectedBg, isNotNull);

    final darkUnselectedRatio =
        contrastRatio(darkUnselectedFg!, darkUnselectedBg!);
    final darkSelectedRatio = contrastRatio(darkSelectedFg!, darkSelectedBg!);

    expect(darkUnselectedRatio, greaterThanOrEqualTo(4.5));
    expect(darkSelectedRatio, greaterThanOrEqualTo(4.5));
  });
}
