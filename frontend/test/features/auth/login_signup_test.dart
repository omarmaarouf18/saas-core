import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/features/auth/otp_page.dart';
import 'package:frontend/features/auth/signup_page.dart';

import 'auth_harness.dart';

Future<void> _pump(WidgetTester tester, AuthTestDeps deps, Widget page,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(authApp(deps, page, locale: locale));
  await tester.pumpAndSettle();
}

Future<void> _fillLogin(WidgetTester tester,
    {String email = 'mona@example.com',
    String password = 'secret-pass'}) async {
  await typeInto(tester, 'login_email', email);
  await typeInto(tester, 'login_password', password);
}

void main() {
  group('sign in', () {
    testWidgets('validates email and password before calling the server',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const LoginPage());
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);

      await typeInto(tester, 'login_email', 'not-an-email');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('Enter an email like name@example.com'), findsOneWidget);
      expect(deps.auth.calls, isEmpty);
    });

    testWidgets('2FA account: opens the code page with the dev code',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const LoginPage());
      await _fillLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();
      expect(deps.auth.calls, ['login:mona@example.com']);
      expect(find.byType(OtpPage), findsOneWidget);
      expect(find.text('mona@example.com'), findsOneWidget);
      expect(find.byKey(const Key('otp_dev_banner')), findsOneWidget);
      expect(deps.nav.homes, 0);
    });

    testWidgets('2FA challenge: "send again" resends the sign-in code',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const LoginPage());
      await _fillLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.byKey(const Key('otp_resend')));
      await tester.pump();
      // POST /auth/resend-otp for the challenge's email (USER-AUTH-BE
      // item 6 resends a pending login challenge, not only a sign-up).
      expect(deps.auth.calls,
          ['login:mona@example.com', 'resendOtp:mona@example.com']);
      expect(find.text('We sent you a new code.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('no second step: goes home', (tester) async {
      final deps = AuthTestDeps()..auth.loginAuthenticates = true;
      await _pump(tester, deps, const LoginPage());
      await _fillLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();
      expect(deps.nav.homes, 1);
      expect(find.byType(OtpPage), findsNothing);
    });

    testWidgets('loading, then a server error banner with retry',
        (tester) async {
      final deps = AuthTestDeps();
      deps.auth.gates['login'] = Completer<void>();
      deps.auth.failNext['login'] =
          const AuthFailure('invalid email or password', status: 401);
      await _pump(tester, deps, const LoginPage());
      await _fillLogin(tester);
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // A second tap while in flight is ignored.
      await tester.tap(find.byKey(const Key('login_submit')));
      deps.auth.gates.remove('login')!.complete();
      await tester.pumpAndSettle();
      expect(deps.auth.calls.length, 1);
      expect(find.text('invalid email or password'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.auth.calls.length, 2);
      expect(find.byKey(const Key('login_error')), findsNothing);
    });

    testWidgets('language pill switches to Arabic, theme icon cycles',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const LoginPage());
      await tester.tap(find.byKey(const Key('login_language')));
      await tester.pumpAndSettle();
      expect(deps.locale.set, [ar]);
      expect(find.text('أهلاً بيك'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_theme')));
      await tester.pumpAndSettle();
      expect(deps.theme.themeMode, ThemeMode.dark);
      await tester.tap(find.byKey(const Key('login_theme')));
      await tester.pumpAndSettle();
      expect(deps.theme.themeMode, ThemeMode.system);
      await tester.tap(find.byKey(const Key('login_theme')));
      await tester.pumpAndSettle();
      expect(deps.theme.themeMode, ThemeMode.light);
    });

    testWidgets(
        'forgot password hands over the typed email and prefills '
        'the email the reset ended with', (tester) async {
      final deps = AuthTestDeps()..nav.resetResult = 'new@example.com';
      await _pump(tester, deps, const LoginPage());
      await typeInto(tester, 'login_email', ' mona@example.com ');
      await tester.tap(find.byKey(const Key('login_forgot')));
      await tester.pumpAndSettle();
      expect(deps.nav.resets, ['mona@example.com']);
      expect(find.text('new@example.com'), findsOneWidget);
    });

    testWidgets('sign-up link opens sign-up, back returns', (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const LoginPage());
      await tester.tap(find.text('Create one'));
      await tester.pumpAndSettle();
      expect(find.byType(SignupPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('auth_back')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('sign up', () {
    testWidgets('customer is preselected; couriers are pointed to owners',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const SignupPage());
      expect(
          find.text('Couriers get their accounts from their business owner.'),
          findsOneWidget);
      await typeInto(tester, 'signup_name', 'Mona Ali');
      await typeInto(tester, 'signup_email', 'mona@example.com');
      await typeInto(tester, 'signup_password', 'long-enough-1');
      await tester.tap(find.byKey(const Key('signup_submit')));
      await tester.pumpAndSettle();
      expect(deps.auth.calls, ['signup:mona@example.com|Mona Ali|user']);
      expect(find.byType(OtpPage), findsOneWidget);
    });

    testWidgets('business owner role is sent as owner', (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const SignupPage());
      await tester.tap(find.byKey(const Key('signup_role_owner')));
      await typeInto(tester, 'signup_name', 'منى علي');
      await typeInto(tester, 'signup_email', 'mona@example.com');
      await typeInto(tester, 'signup_password', 'long-enough-1');
      await tester.tap(find.byKey(const Key('signup_submit')));
      await tester.pumpAndSettle();
      expect(deps.auth.calls.single, endsWith('|owner'));
    });

    testWidgets('client checks: name rules and password length',
        (tester) async {
      final deps = AuthTestDeps();
      await _pump(tester, deps, const SignupPage());
      await typeInto(tester, 'signup_name', 'Mo');
      await typeInto(tester, 'signup_email', 'mona@example.com');
      await typeInto(tester, 'signup_password', 'short');
      await tester.tap(find.byKey(const Key('signup_submit')));
      await tester.pump();
      expect(find.text('The name needs at least 3 letters'), findsOneWidget);
      expect(
          find.text('Password must be at least 8 characters'), findsOneWidget);

      await typeInto(tester, 'signup_name', 'Mona!');
      await tester.tap(find.byKey(const Key('signup_submit')));
      await tester.pump();
      expect(
          find.text('Use letters, numbers, spaces or _ only'), findsOneWidget);
      expect(deps.auth.calls, isEmpty);
    });

    for (final (reason, enText, arText) in [
      (
        'password is too common',
        "This password is too common — pick a less guessable one.",
        'الباسورد ده شائع أوي — اختار واحد صعب التخمين.'
      ),
      (
        'password must be at least 8 characters',
        'Password must be at least 8 characters',
        'الباسورد لازم يكون 8 حروف على الأقل'
      ),
    ]) {
      for (final locale in bothLocales) {
        testWidgets('server weak_password "$reason" is localized [$locale]',
            (tester) async {
          final deps = AuthTestDeps();
          // The provider's banner text is English; the page localizes.
          deps.auth.failNext['signup'] = AuthFailure(
              'This password is too common — pick a less guessable one.',
              status: 400,
              code: 'weak_password',
              reason: reason);
          await _pump(tester, deps, const SignupPage(), locale: locale);
          await typeInto(tester, 'signup_name', 'Mona Ali');
          await typeInto(tester, 'signup_email', 'mona@example.com');
          await typeInto(tester, 'signup_password', 'password123');
          await tester.tap(find.byKey(const Key('signup_submit')));
          await tester.pumpAndSettle();
          final banner = find.byKey(const Key('signup_error'));
          expect(
              find.descendant(
                  of: banner,
                  matching: find.text(locale == ar ? arText : enText)),
              findsOneWidget);
          expect(find.byType(OtpPage), findsNothing);
        });
      }
    }
  });
}
