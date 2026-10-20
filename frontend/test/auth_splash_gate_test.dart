import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as global;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/main.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/screens/signup_screen.dart';
import 'package:frontend/widgets/primary_button.dart';

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
/// only the getters the gate consults (isRestoringSession, isLoading,
/// isAuthenticated), so the restore timing is deterministic without secure
/// storage or networking. HOTFIX-LOGIN: login/signup are scripted like the
/// real provider (isLoading true for the whole request, held on a
/// completer) so the gate's behaviour during a request is observable.
class GateAuthProvider extends AuthProvider {
  GateAuthProvider(super.apiClient);

  bool mockRestoring = false;
  bool mockLoading = false;
  String? mockToken;
  String mockRole = 'owner';

  /// Holds login/signup mid-request until completed by the test.
  Completer<void>? requestGate;

  /// Login signs straight in (employee, no 2FA) when true; otherwise it
  /// returns a code like an owner or customer login.
  bool loginAuthenticates = false;

  @override
  bool get isRestoringSession => mockRestoring;

  @override
  bool get isLoading => mockLoading;

  @override
  String? get error => null;

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
          role: mockRole,
          kycStatus: 'approved',
        );

  Future<void> _request() async {
    mockLoading = true;
    notifyListeners();
    await requestGate?.future;
    mockLoading = false;
  }

  @override
  Future<String?> login(String email, String password) async {
    await _request();
    if (loginAuthenticates) mockToken = 'gate-jwt';
    notifyListeners();
    return loginAuthenticates ? null : '123456';
  }

  @override
  Future<String?> signup(
      String email, String username, String password, String role) async {
    await _request();
    notifyListeners();
    return '654321';
  }

  @override
  Future<void> fetchUserProfile() async {}

  void becomeAuthed() {
    mockToken = 'gate-jwt';
    mockRestoring = false;
    mockLoading = false;
    notifyListeners();
  }

  void revertToLoggedOut() {
    mockToken = null;
    mockRestoring = false;
    mockLoading = false;
    notifyListeners();
  }
}

class _StubEmployeeJobsProvider extends EmployeeJobsProvider {
  _StubEmployeeJobsProvider(super.apiClient);

  @override
  List<Job> get jobs => const [];

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

class _StubEmployeeLocationProvider extends EmployeeLocationProvider {
  _StubEmployeeLocationProvider(super.apiClient);

  @override
  LocationSharingStatus get status => LocationSharingStatus.idle;
  @override
  Future<void> startTracking(String jobId, String userToken) async {}
  @override
  Future<void> startAvailabilityTracking(String userToken) async {}
  @override
  Future<void> stopTracking({bool notify = true}) async {}
  @override
  Future<void> stopAvailabilityTracking() async {}
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
      ChangeNotifierProvider<EmployeeJobsProvider>(
          create: (_) => _StubEmployeeJobsProvider(apiClient)),
      ChangeNotifierProvider<EmployeeLocationProvider>(
          create: (_) => _StubEmployeeLocationProvider(apiClient)),
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
      locale: Locale('en'),
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
    // A launch restore raises both flags, like AuthProvider._tryAutoLogin.
    final auth = GateAuthProvider(ApiClient())
      ..mockRestoring = true
      ..mockLoading = true;

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
  group('HOTFIX-LOGIN: a sign-in request keeps the signed-out screen mounted',
      () {
    Future<void> fillLogin(WidgetTester tester) async {
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'mona@example.com');
      await tester.enterText(fields.at(1), 'secret-pass');
    }

    testWidgets('customer/owner login that needs a code pushes OtpScreen',
        (tester) async {
      final auth = GateAuthProvider(ApiClient())
        ..requestGate = Completer<void>();
      await tester.pumpWidget(createGateApp(auth));
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);

      await fillLogin(tester);
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      // Mid-request: isLoading is true, but this is not a session restore,
      // so the gate keeps the login screen instead of the splash.
      expect(auth.isLoading, isTrue);
      expect(find.byKey(const Key('auth_splash_screen')), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);

      auth.requestGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.byKey(const Key('auth_splash_screen')), findsNothing);
    });

    testWidgets('sign-up pushes OtpScreen', (tester) async {
      final auth = GateAuthProvider(ApiClient())
        ..requestGate = Completer<void>();
      await tester.pumpWidget(createGateApp(auth));
      await tester.pump();

      await tester.tap(find.text("Don't have an account? Sign Up"));
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsOneWidget);

      final fields = find.byType(TextFormField);
      // Field order on the sign-up form: username, email, password.
      await tester.enterText(fields.at(0), 'newbie');
      await tester.enterText(fields.at(1), 'new@example.com');
      await tester.enterText(fields.at(2), 'Secret-pass-123');
      await tester.tap(find.byKey(const Key('signup_role_customer')));
      await tester.pump();
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(auth.isLoading, isTrue);
      expect(find.byKey(const Key('auth_splash_screen')), findsNothing);

      auth.requestGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(OtpScreen), findsOneWidget);
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('employee login (no code) lands on HomeScreen', (tester) async {
      final auth = GateAuthProvider(ApiClient())
        ..mockRole = 'employee'
        ..loginAuthenticates = true
        ..requestGate = Completer<void>();
      await tester.pumpWidget(createGateApp(auth));
      await tester.pump();

      await fillLogin(tester);
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(find.byKey(const Key('auth_splash_screen')), findsNothing);

      auth.requestGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(OtpScreen), findsNothing);
    });
  });
}
