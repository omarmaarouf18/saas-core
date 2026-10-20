import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as global;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';

/// Marketplace stub: HomeScreen's reputation FutureBuilder fetches ratings
/// through it; the stub returns without network traffic.
class StubMarketplaceProvider extends MarketplaceProvider {
  StubMarketplaceProvider(super.apiClient);

  @override
  Future<Map<String, dynamic>> fetchRatings(String token) async {
    return {'average_rating': 4.8, 'count': 25};
  }

  @override
  List<Job> get customerJobs => [];
}

/// UX-17: AuthProvider-driven launch router test. The fake provider controls
/// only the two getters the gate consults (isLoading, isAuthenticated), so
/// the restore timing is deterministic without secure storage or networking.
class GateAuthProvider extends AuthProvider {
  GateAuthProvider(super.apiClient);

  bool mockLoading = false;
  String? mockToken;

  @override
  bool get isLoading => mockLoading;

  @override
  String? get token => mockToken;

  @override
  bool get isAuthenticated => mockToken != null;

  @override
  UserProfile? get user => mockToken == null
      ? null
      : UserProfile(
          id: 'gate-user-1',
          email: 'gate@example.com',
          username: 'gate_user',
          role: 'owner',
          kycStatus: 'approved',
        );

  void becomeAuthed() {
    mockToken = 'gate-jwt';
    mockLoading = false;
    notifyListeners();
  }

  void revertToLoggedOut() {
    mockToken = null;
    mockLoading = false;
    notifyListeners();
  }
}

Widget createGateApp(GateAuthProvider auth) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<OwnerProvider>(
          create: (_) => OwnerProvider(apiClient)),
      ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => StubMarketplaceProvider(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
        create: (_) => NotificationsProvider(
          apiClient,
          // Never touches dart:io in tests; the gate test is offline.
          sseStreamSource: ({required method, required url, required header}) =>
              const Stream.empty(),
        ),
      ),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        global.GlobalMaterialLocalizations.delegate,
        global.GlobalWidgetsLocalizations.delegate,
        global.GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: AuthGate(),
    ),
  );
}

void main() {
  testWidgets(
      'UX-17 auth gate: loading shows splash, authed shows home, '
      'logged out shows login; no LoginScreen frame while loading',
      (tester) async {
    final auth = GateAuthProvider(ApiClient())..mockLoading = true;

    await tester.pumpWidget(createGateApp(auth));

    // Frame 1 during restore: neutral splash, never login, never home.
    expect(find.byKey(const Key('auth_splash_screen')), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);

    // Extra restore frames (slow storage read) stay on the splash.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('auth_splash_screen')), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // Session restored (stored token found): splash to home, no login flash.
    auth.becomeAuthed();
    await tester.pump();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(const Key('auth_splash_screen')), findsNothing);

    // Logged-out verdict (no stored session): router settles on login.
    auth.revertToLoggedOut();
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets(
      'UX-17 auth gate: unauthenticated start routes to login '
      'without ever rendering the splash', (tester) async {
    final auth = GateAuthProvider(ApiClient())..mockLoading = false;

    await tester.pumpWidget(createGateApp(auth));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('auth_splash_screen')), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
