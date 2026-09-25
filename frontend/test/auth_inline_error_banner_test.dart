import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/signup_screen.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/widgets/primary_button.dart';

// Step-1 coverage for audit findings A1/A2/A3 (UI_UX_AUDIT_2026-09.md):
// login, signup, and OTP must surface auth failures in a persistent
// ThemedErrorBanner (mirroring forgot_password_screen.dart), with the
// error snackbar kept only as a transient supplement. Each test below
// pumps PAST the snackbar window (AppMotion.snackBarDisplay = 2s) and
// asserts the banner is still present.
//
// NOTE on the snackbar: these screens pass `onRetry`, and Material makes
// any action-bearing SnackBar persistent by default
// (`persist = persist ?? action != null` in the framework's SnackBar),
// so the snackbar is NOT asserted absent — it legitimately outlives the
// 2s window too. The banner is asserted because it is the durable,
// in-place signal anchored to the form; the floating snackbar is not.

Widget _authApp(AuthProvider authProvider, {required Widget home}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: quickDeliveryTheme,
      home: home,
    ),
  );
}

class _BannerMockApiClient extends ApiClient {
  _BannerMockApiClient() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/login') {
      throw ApiClientException(
        'invalid email or password',
        statusCode: 401,
      );
    } else if (path == '/auth/signup') {
      throw ApiClientException(
        'email already registered',
        statusCode: 400,
      );
    } else if (path == '/auth/verify-otp') {
      throw ApiClientException(
        'invalid or expired OTP code',
        statusCode: 401,
      );
    } else if (path == '/auth/resend-otp') {
      throw ApiClientException(
        'too many attempts. Please try again in 30 seconds.',
        statusCode: 429,
      );
    }
    return {'status': 'ok'};
  }
}

Future<void> _enterOtpBoxes(WidgetTester tester, String code) async {
  for (int i = 0; i < 6; i++) {
    await tester.enterText(find.byKey(Key('otp_box_$i')), code[i]);
    await tester.pump();
  }
}

void _largeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('A1 login inline error banner', () {
    testWidgets(
        'failed login shows a persistent banner that outlives the snackbar',
        (WidgetTester tester) async {
      final authProvider = AuthProvider(_BannerMockApiClient());
      await tester
          .pumpWidget(_authApp(authProvider, home: const LoginScreen()));
      await tester.pumpAndSettle();

      // No banner before any submit attempt.
      expect(find.byKey(const Key('login_error_banner')), findsNothing);

      await tester.enterText(
          find.byType(TextFormField).at(0), 'user@example.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass');
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);
      expect(find.text('invalid email or password'), findsWidgets);

      // Pump past the 2s snackbar window: the persistent banner must
      // survive it (the retry-bearing snackbar itself persists by
      // Material default — see file header — so only the banner and
      // the no-navigation invariant are asserted here).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_error_banner')), findsOneWidget);
      // Still on the login screen — no navigation on failure.
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('A2 signup inline error banner', () {
    testWidgets(
        'failed signup shows a persistent banner that outlives the snackbar',
        (WidgetTester tester) async {
      final authProvider = AuthProvider(_BannerMockApiClient());
      _largeViewport(tester);
      await tester
          .pumpWidget(_authApp(authProvider, home: const SignupScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signup_error_banner')), findsNothing);

      await tester.enterText(find.byType(TextFormField).at(0), 'takenuser');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'taken@example.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'secret123');
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signup_error_banner')), findsOneWidget);
      expect(find.text('email already registered'), findsWidgets);

      // Pump past the 2s snackbar window: the persistent banner must
      // survive it (see file header on why the snackbar itself is not
      // asserted absent).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signup_error_banner')), findsOneWidget);
      expect(find.byType(SignupScreen), findsOneWidget);
    });
  });

  group('A3 OTP inline error banners', () {
    testWidgets(
        'failed verify shows the verify banner (not resend) past the snackbar window',
        (WidgetTester tester) async {
      final authProvider = AuthProvider(_BannerMockApiClient());
      _largeViewport(tester);
      await tester.pumpWidget(_authApp(authProvider,
          home: const OtpScreen(email: 'user@example.com')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otp_verify_error_banner')), findsNothing);
      expect(find.byKey(const Key('otp_resend_error_banner')), findsNothing);

      // Typing the 6th digit auto-submits via onCompleted (existing
      // otp_screen contract) and the mock rejects the code.
      await _enterOtpBoxes(tester, '000000');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otp_verify_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('otp_resend_error_banner')), findsNothing);
      expect(find.text('invalid or expired OTP code'), findsWidgets);

      // Pump past the 2s snackbar window: the persistent banner must
      // survive it (see file header on why the snackbar itself is not
      // asserted absent).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('otp_verify_error_banner')), findsOneWidget);
    });

    testWidgets(
        'failed resend shows the resend banner (not verify) past the snackbar window',
        (WidgetTester tester) async {
      final authProvider = AuthProvider(_BannerMockApiClient());
      _largeViewport(tester);
      await tester.pumpWidget(_authApp(authProvider,
          home: const OtpScreen(email: 'user@example.com')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('otp_resend_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otp_resend_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('otp_verify_error_banner')), findsNothing);
      expect(find.textContaining('try again in 30 seconds.'), findsWidgets);

      // Pump past the 2s snackbar window: the persistent banner must
      // survive it (see file header on why the snackbar itself is not
      // asserted absent).
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('otp_resend_error_banner')), findsOneWidget);
    });
  });
}
