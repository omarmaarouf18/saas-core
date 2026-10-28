import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/l10n/l10n.dart';

import 'core/api_client.dart';
import 'core/app_version.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/update_gate.dart';
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
import 'providers/service_photo_store.dart';
import 'services/local_notifications.dart';
import 'services/notification_tap_router.dart';
import 'services/push_notification_service.dart';
import 'services/push_setup.dart';
import 'features/verification/rejection_dialog_host.dart';
import 'ui/gallery/qd_gallery_screen.dart';
import 'ui/qd_licenses.dart';
import 'ui/qd_theme.dart';

class DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = bypassBadCertificate;
  }
}

/// Library-level so both [main] (426 wiring) and [MyApp] (MaterialApp) share
/// one navigator instance.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Push (PUSH-FCM): Firebase from the build's google-services.json. A
  // build without it, or any Firebase error, logs one line and runs with
  // push off; nothing else changes.
  await initPushFirebase();

  // Wire HTTP certificate overrides in debug mode for self-signed certificates.
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }

  // IBM Plex Sans Arabic (redesign A) ships under the SIL OFL, which asks
  // for its license to be shown with the app.
  registerQdFontLicenses();

  final apiClient = ApiClient(appVersion: kAppVersion);

  // HTTP 426 forced-update gate (QA audit A5): route any upgrade-required
  // response to the blocking UpdateRequiredPage instead of letting it
  // surface as an unmapped generic error.
  apiClient.onUpdateRequired = UpdateGate(appNavigatorKey).handle;

  // Push (PUSH-FCM): the qd_default notification channel, in the app
  // language; the token and permission, shared by sign-in and the pages.
  final localNotifier = PluginLocalNotifier();
  final pushService = PushNotificationService(apiClient: apiClient);
  // Created here so a foreground push reaches the in-app list and badge.
  final notifications = NotificationsProvider(apiClient);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<PushNotificationService>.value(
            value: pushService),
        ChangeNotifierProvider(
            create: (_) => AuthProvider(apiClient, pushService: pushService)),
        ChangeNotifierProvider(create: (_) => OwnerProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => EmployeeJobsProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => MarketplaceProvider(apiClient)),
        ChangeNotifierProvider(create: (_) => ChatProvider(apiClient)),
        ChangeNotifierProvider<NotificationsProvider>.value(
            value: notifications),
        ChangeNotifierProvider(create: (_) => MapTrackingProvider(apiClient)),
        ChangeNotifierProvider(
            create: (_) => ReconciliationProvider(apiClient)),
        ChangeNotifierProvider(
            create: (_) => EmployeeLocationProvider(apiClient)),
      ],
      // Service photos load with the JWT and are cached for every page.
      child: ServicePhotoScope(
        store: ServicePhotoStore(apiClient),
        // Push taps (cold start, background, foreground) for the shells;
        // a foreground push shows on qd_default and joins the list.
        child: NotificationTapScope(
          router: NotificationTapRouter(
            display: localNotifier,
            onForeground: notifications.addFromPush,
          )..start(),
          child: MyApp(localNotifier: localNotifier),
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.localNotifier});

  /// Creates the push notification channel (PUSH-FCM); none in tests.
  final LocalNotifier? localNotifier;

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
      navigatorKey: appNavigatorKey,
      title: 'Quick Delivery',
      // Redesign A, app-wide (FE-CLEANUP): every page, dialog and sheet
      // gets the QdColors extension from here.
      theme: qdLightTheme,
      darkTheme: qdDarkTheme,
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
      builder: (context, child) {
        // The push token carries the app language (PUSH-L10N).
        final host = PushLocaleSync(
          child: VerificationRejectedHost(
            navigatorKey: appNavigatorKey,
            child: child,
          ),
        );
        final notifier = localNotifier;
        return notifier == null
            ? host
            : PushChannelSync(notifier: notifier, child: host);
      },
      onGenerateRoute: (settings) {
        // Debug-only redesign A gallery (FE-DS); never in release builds.
        if (kDebugMode && settings.name == QdGalleryScreen.routeName) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const QdGalleryScreen(),
          );
        }
        return null;
      },
      home: const AuthGate(),
    );
  }
}
