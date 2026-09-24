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
import 'package:frontend/screens/forgot_password_screen.dart';
import 'package:frontend/screens/reset_password_otp_screen.dart';
import 'package:frontend/screens/reset_password_new_screen.dart';
import 'package:frontend/screens/login_screen.dart';

Widget _flowApp(AuthProvider authProvider, {Widget? home}) {
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
      home: home ?? const ForgotPasswordScreen(),
    ),
  );
}

class MockAuthApiClient extends ApiClient {
  int forgotPasswordCalls = 0;
  String? lastForgotEmail;
  int verifyCalls = 0;
  int resetCalls = 0;
  Map<String, dynamic>? lastResetBody;

  /// 'ok' verifies only the dev code 654321; 'wrong' rejects everything
  /// with 401; 'locked' rejects everything with 429.
  String verifyMode = 'ok';

  /// 'ok' succeeds; 'expired' rejects with 401 (lapsed verification).
  String resetMode = 'ok';

  /// When false, /auth/forgot-password omits dev_otp (prod-like).
  bool returnDevOtp = true;

  MockAuthApiClient() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/forgot-password') {
      forgotPasswordCalls++;
      lastForgotEmail = body['email'] as String?;
      if (returnDevOtp) {
        return {'message': 'OTP sent', 'dev_otp': '654321'};
      }
      return {'message': 'OTP sent'};
    } else if (path == '/auth/reset-password/verify-code') {
      verifyCalls++;
      if (verifyMode == 'locked') {
        throw ApiClientException(
          'too many attempts from this IP. Please try again in 45 seconds.',
          statusCode: 429,
        );
      }
      if (verifyMode == 'wrong' || body['otp'] != '654321') {
        throw ApiClientException(
          'invalid or expired OTP code',
          statusCode: 401,
        );
      }
      return {'status': 'success', 'message': 'reset code verified'};
    } else if (path == '/auth/reset-password') {
      resetCalls++;
      lastResetBody = Map<String, dynamic>.from(body);
      if (resetMode == 'expired') {
        throw ApiClientException(
          'invalid or expired reset verification',
          statusCode: 401,
        );
      }
      return {'status': 'success', 'message': 'password reset successfully'};
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

void _dismissSnackBar(WidgetTester tester) {
  ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
      .removeCurrentSnackBar();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Two-phase reset flow (ADR-0026)', () {
    late MockAuthApiClient mockApiClient;
    late AuthProvider authProvider;

    setUp(() {
      mockApiClient = MockAuthApiClient();
      // NOTE: AuthProvider must be constructed inside each testWidgets body,
      // not here: constructing it in setUp() leaves the first pumpAndSettle
      // hanging (the constructor's async auto-login outlives the setUp
      // zone). Body construction is also this repo's dominant test style.
    });

    testWidgets(
        'Screen 1 collects only the email and pushes the OTP screen carrying it',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      await tester.pumpWidget(_flowApp(authProvider));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('forgot_password_email_field')), findsOneWidget);
      expect(
          find.byKey(const Key('request_reset_code_button')), findsOneWidget);
      // OTP / password concerns live on later screens now.
      expect(find.byKey(const Key('reset_code_otp_field')), findsNothing);
      expect(find.byKey(const Key('reset_new_password_field')), findsNothing);
      expect(
          find.byKey(const Key('submit_reset_password_button')), findsNothing);

      await tester.enterText(
          find.byKey(const Key('forgot_password_email_field')),
          'user@example.com');
      await tester.tap(find.byKey(const Key('request_reset_code_button')));
      await tester.pumpAndSettle();

      expect(mockApiClient.forgotPasswordCalls, 1);
      expect(mockApiClient.lastForgotEmail, 'user@example.com');
      // Screen 2 opens with the dev OTP banner carried over from screen 1.
      expect(find.byType(ResetPasswordOtpScreen), findsOneWidget);
      expect(find.text('Dev OTP Code: 654321'), findsOneWidget);
    });

    testWidgets('Wrong code on screen 2 stays put with an error, no screen 3',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      mockApiClient.returnDevOtp = false;
      await tester.pumpWidget(_flowApp(authProvider,
          home: const ResetPasswordOtpScreen(email: 'user@example.com')));
      await tester.pumpAndSettle();

      await _enterOtpBoxes(tester, '000000');
      await tester.tap(find.byKey(const Key('verify_reset_code_button')));
      await tester.pumpAndSettle();

      expect(mockApiClient.verifyCalls, 1);
      expect(find.byKey(const Key('reset_code_error_banner')), findsOneWidget);
      expect(find.text('invalid or expired OTP code'), findsOneWidget);
      expect(find.byType(ResetPasswordNewScreen), findsNothing);
    });

    testWidgets('429 on screen 2 shows the lockout wait-time message',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      mockApiClient.verifyMode = 'locked';
      mockApiClient.returnDevOtp = false;
      await tester.pumpWidget(_flowApp(authProvider,
          home: const ResetPasswordOtpScreen(email: 'user@example.com')));
      await tester.pumpAndSettle();

      await _enterOtpBoxes(tester, '123456');
      await tester.tap(find.byKey(const Key('verify_reset_code_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('reset_code_lockout_banner')), findsOneWidget);
      expect(find.textContaining('try again in 45 seconds.'), findsOneWidget);
      expect(find.byType(ResetPasswordNewScreen), findsNothing);
    });

    testWidgets('Resend from screen 2 reuses the screen-1 email, no re-entry',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      await tester.pumpWidget(_flowApp(authProvider));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('forgot_password_email_field')),
          'user@example.com');
      await tester.tap(find.byKey(const Key('request_reset_code_button')));
      await tester.pumpAndSettle();
      _dismissSnackBar(tester);
      await tester.pump();

      await tester.tap(find.byKey(const Key('resend_reset_code_button')));
      await tester.pumpAndSettle();

      expect(mockApiClient.forgotPasswordCalls, 2);
      expect(mockApiClient.lastForgotEmail, 'user@example.com');
      expect(find.byType(ResetPasswordOtpScreen), findsOneWidget);
    });

    testWidgets(
        'Full run screen 1 → 2 → 3 → login; reset body carries no raw code',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      await tester.pumpWidget(_flowApp(authProvider));
      await tester.pumpAndSettle();

      // Screen 1 → 2 (dev OTP auto-fills the correct code on screen 2).
      await tester.enterText(
          find.byKey(const Key('forgot_password_email_field')),
          'user@example.com');
      await tester.tap(find.byKey(const Key('request_reset_code_button')));
      await tester.pumpAndSettle();
      _dismissSnackBar(tester);
      await tester.pump();
      expect(find.byType(ResetPasswordOtpScreen), findsOneWidget);

      // Screen 2 → 3.
      await tester.tap(find.byKey(const Key('verify_reset_code_button')));
      await tester.pumpAndSettle();
      expect(mockApiClient.verifyCalls, 1);
      expect(find.byType(ResetPasswordNewScreen), findsOneWidget);

      // Screen 3 → login.
      await tester.enterText(
          find.byKey(const Key('reset_new_password_field')), 'newSecret123');
      await tester.enterText(
          find.byKey(const Key('reset_confirm_password_field')),
          'newSecret123');
      final submitBtn = find.byKey(const Key('submit_new_password_button'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(mockApiClient.resetCalls, 1);
      expect(mockApiClient.lastResetBody!['email'], 'user@example.com');
      expect(mockApiClient.lastResetBody!['new_password'], 'newSecret123');
      expect(mockApiClient.lastResetBody!.containsKey('otp'), isFalse);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Lapsed verification on screen 3 shows the restart message',
        (WidgetTester tester) async {
      authProvider = AuthProvider(mockApiClient);
      _largeViewport(tester);
      mockApiClient.resetMode = 'expired';
      await tester.pumpWidget(_flowApp(authProvider,
          home: const ResetPasswordNewScreen(email: 'user@example.com')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('reset_new_password_field')), 'newSecret123');
      await tester.enterText(
          find.byKey(const Key('reset_confirm_password_field')),
          'newSecret123');
      await tester.tap(find.byKey(const Key('submit_new_password_button')));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('reset_password_error_banner')), findsOneWidget);
      expect(
          find.textContaining('restart from the email step'), findsOneWidget);
      // Still on screen 3 — no silent loop, no login navigation.
      expect(find.byType(ResetPasswordNewScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
