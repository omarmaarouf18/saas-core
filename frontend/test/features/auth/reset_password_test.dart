import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/auth_nav.dart';
import 'package:frontend/features/auth/reset_password_page.dart';

import 'auth_harness.dart';

/// Opens the reset page from a host page so the result can be observed.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String? result = 'none';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Text('result: $result'),
          TextButton(
            onPressed: () async {
              final r = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                      builder: (_) => const ResetPasswordPage(
                          initialEmail: 'mona@example.com')));
              setState(() => result = r);
            },
            child: const Text('open'),
          ),
        ]),
      );
}

Future<void> _open(WidgetTester tester, AuthTestDeps deps,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(authApp(deps, const _Host(), locale: locale));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _toPasswordStep(WidgetTester tester, AuthTestDeps deps) async {
  await tester.tap(find.byKey(const Key('reset_send_code')));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // Dev code auto-filled: confirm.
  await tester.tap(find.byKey(const Key('otp_confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _enterPasswords(WidgetTester tester, String a, [String? b]) async {
  await typeInto(tester, 'reset_new_password', a);
  await typeInto(tester, 'reset_confirm_password', b ?? a);
  await tester.tap(find.byKey(const Key('reset_save')));
  await tester.pump();
}

void main() {
  testWidgets(
      'three steps: email, code, new password, back to sign in '
      'with the email', (tester) async {
    final deps = AuthTestDeps();
    await _open(tester, deps);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('mona@example.com'), findsOneWidget); // prefilled

    await tester.tap(find.byKey(const Key('reset_send_code')));
    await tester.pump();
    expect(deps.auth.calls, ['forgotPassword:mona@example.com']);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('We sent a code to your email.'), findsOneWidget);
    expect(find.byKey(const Key('otp_dev_banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('otp_confirm')));
    await tester.pump();
    expect(deps.auth.calls.last, 'verifyResetCode:mona@example.com|123456');
    expect(find.text('Step 3 of 3'), findsOneWidget);

    await _enterPasswords(tester, 'new-password-1');
    await tester.pumpAndSettle();
    expect(deps.auth.calls.last,
        'resetPassword:mona@example.com|reset-token|new-password-1');
    expect(find.text('Your password was changed. Sign in with the new one.'),
        findsOneWidget);
    expect(find.text('result: mona@example.com'), findsOneWidget);
  });

  testWidgets('email step: validation and server error with retry',
      (tester) async {
    final deps = AuthTestDeps();
    deps.auth.failNext['forgotPassword'] =
        const AuthFailure('Something went wrong on our end.', status: 500);
    await _open(tester, deps);
    await typeInto(tester, 'reset_email', 'bad');
    await tester.tap(find.byKey(const Key('reset_send_code')));
    await tester.pump();
    expect(find.text('Enter an email like name@example.com'), findsOneWidget);

    await typeInto(tester, 'reset_email', 'mona@example.com');
    await tester.tap(find.byKey(const Key('reset_send_code')));
    await tester.pump();
    expect(find.byKey(const Key('reset_email_error')), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('wrong code stays on step 2; a lockout offers no retry',
      (tester) async {
    final deps = AuthTestDeps()..auth.devOtp = null;
    deps.auth.failNext['verifyResetCode'] =
        const AuthFailure('invalid or expired reset verification', status: 401);
    await _open(tester, deps);
    await tester.tap(find.byKey(const Key('reset_send_code')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('qd_otp_field')), '000000');
    await tester.pump();
    expect(find.byKey(const Key('otp_error')), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);

    deps.auth.failNext['verifyResetCode'] = const AuthFailure(
        'too many attempts. Please try again in 300 seconds.',
        status: 429);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.byKey(const Key('otp_lockout')), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('new password: local checks before any request', (tester) async {
    final deps = AuthTestDeps();
    await _open(tester, deps);
    await _toPasswordStep(tester, deps);
    final before = deps.auth.calls.length;
    await _enterPasswords(tester, 'short');
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    await _enterPasswords(tester, 'new-password-1', 'new-password-2');
    expect(find.text("The two passwords don't match"), findsOneWidget);
    expect(deps.auth.calls.length, before);
  });

  for (final locale in bothLocales) {
    testWidgets('server weak_password reason is localized [$locale]',
        (tester) async {
      final deps = AuthTestDeps();
      deps.auth.failNext['resetPassword'] = const AuthFailure(
          'This password is too common — pick a less guessable one.',
          status: 400,
          code: 'weak_password',
          reason: 'password is too common');
      await _open(tester, deps, locale: locale);
      await _toPasswordStep(tester, deps);
      await _enterPasswords(tester, 'password123');
      await tester.pump();
      expect(find.byKey(const Key('reset_save_error')), findsOneWidget);
      expect(
          find.text(locale == ar
              ? 'الباسورد ده شائع أوي — اختار واحد صعب التخمين.'
              : 'This password is too common — pick a less guessable one.'),
          findsOneWidget);
      expect(find.text(locale == ar ? 'خطوة 3 من 3' : 'Step 3 of 3'),
          findsOneWidget);
    });
  }

  testWidgets('expired token (401): explained, "start again" goes to step 1',
      (tester) async {
    final deps = AuthTestDeps();
    deps.auth.failNext['resetPassword'] =
        const AuthFailure('invalid or expired reset verification', status: 401);
    await _open(tester, deps);
    await _toPasswordStep(tester, deps);
    await _enterPasswords(tester, 'new-password-1');
    await tester.pump();
    expect(find.byKey(const Key('reset_expired')), findsOneWidget);
    await tester.tap(find.text('Start again'));
    await tester.pump();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byKey(const Key('reset_email_error')), findsNothing);
    expect(find.text('mona@example.com'), findsOneWidget);
  });

  testWidgets('no token held: no request, restart offered', (tester) async {
    final deps = AuthTestDeps()..auth.nextResetToken = null;
    await _open(tester, deps);
    await _toPasswordStep(tester, deps);
    // verifyResetCode returned no token: the page stays on step 2.
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('back goes one step back, then closes', (tester) async {
    final deps = AuthTestDeps();
    await _open(tester, deps);
    await _toPasswordStep(tester, deps);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('auth_back')));
    await tester.pump();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('auth_back')));
    await tester.pump();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('auth_back')));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordPage), findsNothing);
    expect(find.text('result: null'), findsOneWidget);
  });

  testWidgets('AuthNav opens the redesigned reset page with the email',
      (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps();
    await tester.pumpWidget(authApp(
        deps,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => const AuthNav()
                .openPasswordReset(context, email: 'mona@example.com'),
            child: const Text('go'),
          ),
        )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(find.text('mona@example.com'), findsOneWidget);
  });
}
