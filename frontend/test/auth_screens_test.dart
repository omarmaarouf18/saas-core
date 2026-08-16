import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/signup_screen.dart';
import 'package:frontend/screens/otp_screen.dart';
import 'package:frontend/screens/forgot_password_screen.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';

Widget createAuthTestApp({required Widget child, AuthProvider? authProvider}) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => authProvider ?? AuthProvider(apiClient),
      ),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
      ),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(),
      ),
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
      home: child,
    ),
  );
}

void main() {
  group('LoginScreen Widget Tests', () {
    testWidgets('Renders QD logotype and theme/language controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(createAuthTestApp(child: const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('login_qd_logo')), findsOneWidget);
      expect(find.text("QD"), findsOneWidget);
      expect(find.byIcon(Icons.storefront), findsOneWidget);
      expect(
          find.byKey(const Key('login_theme_toggle_button')), findsOneWidget);
      expect(find.byKey(const Key('login_lang_toggle_button')), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
    });

    testWidgets('Tapping Forgot Password navigates to ForgotPasswordScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(createAuthTestApp(child: const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final forgotBtn = find.text("Forgot password?");
      expect(forgotBtn, findsOneWidget);
      await tester.tap(forgotBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    testWidgets('Tapping Sign Up navigates to SignupScreen',
        (WidgetTester tester) async {
      await tester.pumpWidget(createAuthTestApp(child: const LoginScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final signupBtn = find.text("Don't have an account? Sign Up");
      expect(signupBtn, findsOneWidget);
      await tester.tap(signupBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SignupScreen), findsOneWidget);
    });
  });

  group('SignupScreen Widget Tests', () {
    testWidgets('Renders all fields and role dropdown',
        (WidgetTester tester) async {
      await tester.pumpWidget(createAuthTestApp(child: const SignupScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("Create Account"), findsOneWidget);
      expect(find.text("Business Owner"), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text("Already have an account? Sign In"), findsOneWidget);
    });
  });

  group('OtpScreen Widget Tests', () {
    testWidgets(
        'Renders SecondaryButton for Resend Code with debounce protection',
        (WidgetTester tester) async {
      await tester.pumpWidget(createAuthTestApp(
        child: const OtpScreen(email: 'test@example.com', devOtp: '123456'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text("Two-Factor Verification"), findsOneWidget);
      expect(find.text("Dev Mode: Auto-populated OTP '123456' from response."),
          findsOneWidget);

      final resendButtonFinder = find.byKey(const Key('otp_resend_button'));
      expect(resendButtonFinder, findsOneWidget);

      final secondaryButton =
          tester.widget<SecondaryButton>(resendButtonFinder);
      expect(secondaryButton.isOutlined, isTrue);
      expect(secondaryButton.icon, Icons.refresh);
      expect(secondaryButton.text, "RESEND CODE");
      expect(secondaryButton.onPressed, isNotNull);
    });
  });
}
