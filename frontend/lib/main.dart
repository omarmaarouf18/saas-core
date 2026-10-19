import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/l10n/l10n.dart';

import 'core/api_client.dart';
import 'core/update_gate.dart';
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
import 'screens/component_library_screen.dart';
import 'widgets/kyc_rejection_dialog_host.dart';
import 'widgets/themed_panel.dart';

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

void main() {
  // Wire HTTP certificate overrides in debug mode for self-signed certificates.
  if (kDebugMode) {
    HttpOverrides.global = DevHttpOverrides();
  }

  // Poppins is bundled under assets/fonts/ — brand typography must render
  // identically offline and never depend on runtime font downloads.
  GoogleFonts.config.allowRuntimeFetching = false;

  final apiClient = ApiClient();

  // HTTP 426 forced-update gate (QA audit A5): route any upgrade-required
  // response to the blocking UpdateRequiredScreen instead of letting it
  // surface as an unmapped generic error.
  apiClient.onUpdateRequired = UpdateGate(appNavigatorKey).handle;

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
      navigatorKey: appNavigatorKey,
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
      builder: (context, child) => KycRejectionDialogHost(
        navigatorKey: appNavigatorKey,
        child: child,
      ),
      onGenerateRoute: (settings) {
        // Debug-only component library route (Storybook-style shared widget
        // catalog). Never registered in release builds.
        if (kDebugMode && settings.name == '/component-library') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const ComponentLibraryScreen(),
          );
        }
        return null;
      },
      home: const AuthGate(),
    );
  }
}

/// UX-17: chooses the launch destination from the live AuthProvider state.
/// While the stored session is being restored (`isLoading`) a neutral splash
/// is shown, so the login screen is never rendered as a flash frame before
/// the session verdict exists.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.isLoading) {
      return const AuthSplashScreen();
    }
    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
  }
}

/// UX-17: neutral launch splash shown while AuthProvider is restoring the
/// stored session. Keeps the app from flashing the login screen (and its
/// auth-only chrome) before the session verdict exists; [AuthGate] routes to
/// Home/Login the moment `isLoading` clears. Theme-aware (no raw colors) and
/// text-free apart from the localized brand wordmark.
class AuthSplashScreen extends StatelessWidget {
  const AuthSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('auth_splash_screen'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ThemedPanel(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storefront,
                    color: AppColors.secondary,
                    size: AppIconSize.md,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'QD',
                    style: AppTypography.titleMd.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.otpFooterBrand,
              style: AppTypography.labelMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
