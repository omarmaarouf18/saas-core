import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/customer_home_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/screens/settings_screen.dart';

class MockApiClient extends ApiClient {
  MockApiClient() : super(baseUrl: 'http://localhost:8080');
}

Widget buildTestApp({
  required Widget child,
  Locale locale = const Locale('ar'),
  AuthProvider? authProvider,
  MarketplaceProvider? marketplaceProvider,
  NotificationsProvider? notificationsProvider,
  ChatProvider? chatProvider,
  LocaleProvider? localeProvider,
}) {
  final client = MockApiClient();
  final auth = authProvider ?? AuthProvider(client);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(
          create: (_) => localeProvider ?? LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => marketplaceProvider ?? MarketplaceProvider(client)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) =>
              notificationsProvider ?? NotificationsProvider(client)),
      ChangeNotifierProvider<ChatProvider>(
          create: (_) => chatProvider ?? ChatProvider(client)),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localization Infrastructure & RTL Tests', () {
    testWidgets(
        '(a1) Arabic locale sets TextDirection.rtl on CustomerHomeScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('ar'),
          child: const CustomerHomeScreen(),
        ),
      );
      await tester.pump();

      final BuildContext context =
          tester.element(find.byType(CustomerHomeScreen));
      expect(Directionality.of(context), equals(TextDirection.rtl));
      expect(find.text('Quick Delivery'), findsWidgets);
    });

    testWidgets(
        '(a2) English locale sets TextDirection.ltr on CustomerHomeScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('en'),
          child: const CustomerHomeScreen(),
        ),
      );
      await tester.pump();

      final BuildContext context =
          tester.element(find.byType(CustomerHomeScreen));
      expect(Directionality.of(context), equals(TextDirection.ltr));
      expect(find.text('Quick Delivery'), findsWidgets);
    });

    testWidgets(
        '(a3) SettingsScreen language selector switches locale dynamically',
        (WidgetTester tester) async {
      final auth = AuthProvider(MockApiClient());
      final localeProvider = LocaleProvider();

      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('en'),
          authProvider: auth,
          localeProvider: localeProvider,
          child: const SettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('language_selector')), findsOneWidget);

      // Tap Arabic button in SegmentedButton
      await tester.tap(find.byKey(const Key('lang_ar_button')));
      await tester.pumpAndSettle();

      expect(localeProvider.locale?.languageCode, equals('ar'));
    });

    testWidgets(
        '(a4) JobStatusScreen renders RTL correctly with Arabic strings',
        (WidgetTester tester) async {
      final job = Job(
        id: 'job-99999999',
        ownerId: 'owner-1',
        userId: 'user-1',
        serviceId: 'service-1',
        status: 'active',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        paymentMethod: 'cod',
        agreedPrice: 25.0,
      );

      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('ar'),
          child: JobStatusScreen(job: job),
        ),
      );
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(JobStatusScreen));
      expect(Directionality.of(context), equals(TextDirection.rtl));
      expect(find.text('حالة الطلب'), findsOneWidget);
    });

    testWidgets('(a5) ChatScreen renders RTL correctly with Arabic strings',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestApp(
          locale: const Locale('ar'),
          child: const ChatScreen(jobId: 'job-12345678'),
        ),
      );
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(ChatScreen));
      expect(Directionality.of(context), equals(TextDirection.rtl));
      expect(find.textContaining('محادثة الطلب'), findsAtLeastNWidgets(1));
    });
  });
}
