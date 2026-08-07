import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/screens/forgot_password_screen.dart';

Widget createForgotPasswordApp(AuthProvider authProvider) {
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
      home: const ForgotPasswordScreen(),
    ),
  );
}

class MockAuthApiClient extends ApiClient {
  bool forgotPasswordCalled = false;
  bool resetPasswordCalled = false;
  String? lastForgotEmail;
  String? lastResetEmail;
  String? lastResetOtp;
  String? lastResetNewPassword;

  MockAuthApiClient() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/forgot-password') {
      forgotPasswordCalled = true;
      lastForgotEmail = body['email'] as String?;
      return {'message': 'OTP sent', 'dev_otp': '654321'};
    } else if (path == '/auth/reset-password') {
      resetPasswordCalled = true;
      lastResetEmail = body['email'] as String?;
      lastResetOtp = body['otp'] as String?;
      lastResetNewPassword = body['new_password'] as String?;
      return {'message': 'password reset successfully'};
    }
    return {'status': 'ok'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Consolidated ForgotPasswordScreen Widget Tests', () {
    late MockAuthApiClient mockApiClient;
    late AuthProvider authProvider;

    setUp(() {
      mockApiClient = MockAuthApiClient();
      authProvider = AuthProvider(mockApiClient);
    });

    testWidgets(
        'renders all fields (Email, OTP, New Password, Confirm Password) and single RESET PASSWORD button on the SAME screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(createForgotPasswordApp(authProvider));

      expect(
          find.byKey(const Key('forgot_password_email_field')), findsOneWidget);
      expect(
          find.byKey(const Key('request_reset_code_button')), findsOneWidget);
      expect(
          find.byKey(const Key('forgot_password_otp_field')), findsOneWidget);
      expect(find.byKey(const Key('forgot_password_new_password_field')),
          findsOneWidget);
      expect(find.byKey(const Key('forgot_password_confirm_password_field')),
          findsOneWidget);
      expect(find.byKey(const Key('submit_reset_password_button')),
          findsOneWidget);

      expect(find.byKey(const Key('password_toggle_button')), findsNWidgets(2));
    });

    testWidgets(
        'executes request code and single-step reset password submission with email, OTP, and new password',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createForgotPasswordApp(authProvider));

      // 1. Enter email and request code
      await tester.enterText(
          find.byKey(const Key('forgot_password_email_field')),
          'user@example.com');
      await tester.tap(find.byKey(const Key('request_reset_code_button')));
      await tester.pumpAndSettle();

      expect(mockApiClient.forgotPasswordCalled, isTrue);
      expect(mockApiClient.lastForgotEmail, 'user@example.com');

      // Dev OTP '654321' auto-populates in OTP field and dev banner shows
      expect(find.text('Dev OTP Code: 654321'), findsOneWidget);

      // Dismiss SnackBar so it doesn't obscure button taps
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
          .removeCurrentSnackBar();
      await tester.pump();

      // 2. Enter new password and confirm password on the SAME screen
      await tester.enterText(
          find.byKey(const Key('forgot_password_new_password_field')),
          'newSecret123');
      await tester.enterText(
          find.byKey(const Key('forgot_password_confirm_password_field')),
          'newSecret123');

      // 3. Submit single RESET PASSWORD action
      final submitBtn = find.byKey(const Key('submit_reset_password_button'));
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(mockApiClient.resetPasswordCalled, isTrue);
      expect(mockApiClient.lastResetEmail, 'user@example.com');
      expect(mockApiClient.lastResetOtp, '654321');
      expect(mockApiClient.lastResetNewPassword, 'newSecret123');
    });
  });
}
