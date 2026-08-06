import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/app_localizations.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/owner_provider.dart';
import 'providers/employee_jobs_provider.dart';
import 'providers/employee_location_provider.dart';
import 'providers/marketplace_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/map_tracking_provider.dart';
import 'providers/reconciliation_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = bypassBadCertificate;
  }
}

void main() {
  // Wire HTTP certificate overrides in debug mode for self-signed certificates.
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }

  final apiClient = ApiClient();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => OwnerProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => EmployeeJobsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => MarketplaceProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => ChatProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => NotificationsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => MapTrackingProvider(apiClient)),
        ChangeNotifierProvider(
            create: (_) => ReconciliationProvider(apiClient)),
        ChangeNotifierProvider(
            create: (_) => EmployeeLocationProvider(apiClient)),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final notifications =
        Provider.of<NotificationsProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.isAuthenticated) {
        notifications.initSse(auth.token!);
      } else {
        notifications.unsubscribe();
      }
    });

    return MaterialApp(
      title: 'Quick Delivery',
      theme: quickDeliveryTheme,
      darkTheme: quickDeliveryDarkTheme,
      themeMode: themeProvider.themeMode,
      locale: localeProvider.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        if (localeProvider.locale != null) {
          return localeProvider.locale;
        }
        if (deviceLocale != null && deviceLocale.languageCode == 'ar') {
          return const Locale('ar');
        }
        return const Locale('en');
      },
      debugShowCheckedModeBanner: false,
      home: auth.isAuthenticated ? const HomeScreen() : const LoginScreen(),
    );
  }
}
