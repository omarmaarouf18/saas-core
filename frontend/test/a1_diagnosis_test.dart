import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/screens/customer_home_screen.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/job.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  UserProfile? user = UserProfile(
    id: 'user-123',
    email: 'customer@example.com',
    username: 'Test User',
    role: 'user',
    kycStatus: 'approved',
  );
  @override
  String? token = 'token';
  @override
  bool isLoading = false;
  @override
  String? error;
  @override
  Future<void> fetchUserProfile() async {}
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockMarketplaceProvider extends ChangeNotifier
    implements MarketplaceProvider {
  @override
  List<MarketplaceService> services = [];
  @override
  List<Job> customerJobs = [];
  @override
  bool isLoading = false;
  @override
  String? error;
  @override
  Future<void> fetchServices({
    bool nearBy = false,
    double lat = 0,
    double lon = 0,
    double radius = 50,
    String sortBy = 'none',
  }) async {}
  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async =>
      customerJobs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockNotificationsProvider extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockThemeProvider extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Diagnose A1: quick search area box redirect and layout',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => MockAuthProvider()),
          ChangeNotifierProvider<MarketplaceProvider>(
              create: (_) => MockMarketplaceProvider()),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => MockNotificationsProvider()),
          ChangeNotifierProvider<ThemeProvider>(
              create: (_) => MockThemeProvider()),
          ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider()),
          ChangeNotifierProvider<ChatProvider>(
              create: (_) => MockChatProvider()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: CustomerHomeScreen(initialTabIndex: 0),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Locate the area search box
    final searchBoxHint = find.text('Enter destination or pickup area...');
    expect(searchBoxHint, findsOneWidget);

    // 2. Identify the enclosing InkWell
    final inkWell =
        find.ancestor(of: searchBoxHint, matching: find.byType(InkWell));
    expect(inkWell, findsOneWidget);

    // 3. Tap the search box and verify it opens the location picker dialog
    await tester.tap(inkWell);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_search_location_picker_dialog')),
        findsOneWidget);

    // 4. Confirming location closes dialog and switches to Services tab (CustomerMarketplaceScreen)
    final confirmBtn = find.byKey(const Key('confirm_search_location_button'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.byType(CustomerMarketplaceScreen), findsOneWidget);
  });

  testWidgets('Diagnose A1: Arabic text and narrow viewport overflow check',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(
              create: (_) => MockAuthProvider()),
          ChangeNotifierProvider<MarketplaceProvider>(
              create: (_) => MockMarketplaceProvider()),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => MockNotificationsProvider()),
          ChangeNotifierProvider<ThemeProvider>(
              create: (_) => MockThemeProvider()),
          ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider()),
          ChangeNotifierProvider<ChatProvider>(
              create: (_) => MockChatProvider()),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('ar'),
          home: CustomerHomeScreen(initialTabIndex: 0),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Inspect the text widget for maxLines and overflow constraints
    final textWidget = tester.widget<Text>(find.byWidgetPredicate(
      (w) => w is Text && (w.data?.contains('التسليم') ?? false),
    ));
    expect(textWidget.maxLines, equals(1));
    expect(textWidget.overflow, equals(TextOverflow.ellipsis));
  });
}
