import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/email_change_sheet.dart';
import 'package:frontend/features/account/my_details_page.dart';
import 'package:frontend/features/account/security_page.dart';

import 'account_harness.dart';

/// Pushes [page] over a host so "back" and pops can be observed.
Future<void> _open(
    WidgetTester tester, AccountTestDeps deps, Widget page) async {
  usePhone(tester);
  await tester.pumpWidget(accountApp(
      deps,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('host'),
          ),
        ),
      )));
  await tester.tap(find.text('host'));
  await tester.pumpAndSettle();
}

FakeAuthFlow _suspended() =>
    FakeAuthFlow(user: FakeAuthFlow.customer(accountStatus: 'suspended'));

void main() {
  group('my details', () {
    testWidgets('prefilled; save sends name and phone, then back',
        (tester) async {
      final deps = AccountTestDeps();
      await _open(tester, deps, const MyDetailsPage());
      expect(find.text('Mona'), findsOneWidget);
      expect(find.text('01001234567'), findsOneWidget);
      expect(find.text('mona@example.com'), findsOneWidget);
      await typeInto(tester, 'details_name', ' Mona Ali ');
      await tester.tap(find.byKey(const Key('details_save')));
      await tester.pumpAndSettle();
      expect(deps.auth.lastProfileUpdate,
          {'username': 'Mona Ali', 'phone': '01001234567'});
      expect(find.text('Your details were saved.'), findsOneWidget);
      expect(find.byType(MyDetailsPage), findsNothing);
    });

    testWidgets('name required; server error with retry', (tester) async {
      final deps = AccountTestDeps();
      deps.auth.failNext['updateOwnProfile'] =
          const AuthFailure('username already taken', status: 409);
      await _open(tester, deps, const MyDetailsPage());
      await typeInto(tester, 'details_name', '  ');
      await tester.tap(find.byKey(const Key('details_save')));
      await tester.pump();
      expect(find.text('Enter your name'), findsOneWidget);
      expect(deps.auth.calls, isEmpty);

      await typeInto(tester, 'details_name', 'Mona');
      await tester.tap(find.byKey(const Key('details_save')));
      await tester.pumpAndSettle();
      expect(find.text('username already taken'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsPage), findsNothing);
    });

    testWidgets('suspended: banner, nothing editable', (tester) async {
      final deps = AccountTestDeps(auth: _suspended());
      await _open(tester, deps, const MyDetailsPage());
      expect(find.byKey(const Key('account_suspended')), findsOneWidget);
      await tester.tap(find.byKey(const Key('details_save')));
      await tester.tap(find.byKey(const Key('details_change_email')));
      await tester.pumpAndSettle();
      expect(deps.auth.calls, isEmpty);
      expect(find.byType(EmailChangeSheet), findsNothing);
    });
  });

  group('email change', () {
    Future<void> openSheet(WidgetTester tester, AccountTestDeps deps) async {
      await _open(tester, deps, const MyDetailsPage());
      await tester.tap(find.byKey(const Key('details_change_email')));
      await tester.pumpAndSettle();
      expect(find.byType(EmailChangeSheet), findsOneWidget);
    }

    testWidgets('step 1 checks; step 2 with dev code; confirm closes',
        (tester) async {
      final deps = AccountTestDeps()..auth.devOtp = '424242';
      await openSheet(tester, deps);
      await typeInto(tester, 'email_change_input', 'nope');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pump();
      expect(find.text('Enter an email like name@example.com'), findsOneWidget);
      await typeInto(tester, 'email_change_input', 'MONA@example.com');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pump();
      expect(find.text('This is already your email'), findsOneWidget);
      expect(deps.auth.calls, isEmpty);

      await typeInto(tester, 'email_change_input', 'new@example.com');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pump();
      expect(deps.auth.calls, ['requestEmailChange:new@example.com']);
      expect(find.text('new@example.com'), findsOneWidget);
      expect(find.text('Test mode: we filled in the code 424242 for you.'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('otp_confirm')));
      await tester.pumpAndSettle();
      expect(deps.auth.calls.last, 'confirmEmailChange:424242');
      expect(find.byType(EmailChangeSheet), findsNothing);
      expect(find.text('Your email was changed.'), findsOneWidget);
    });

    testWidgets('step 2: wrong code shows the error and stays open',
        (tester) async {
      final deps = AccountTestDeps()..auth.devOtp = null;
      deps.auth.failNext['confirmEmailChange'] =
          const AuthFailure('invalid or expired OTP code', status: 401);
      await openSheet(tester, deps);
      await typeInto(tester, 'email_change_input', 'new@example.com');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('qd_otp_field')), '111111');
      await tester.pump();
      expect(find.text('invalid or expired OTP code'), findsOneWidget);
      expect(find.byType(EmailChangeSheet), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('request error with retry; outside tap does not close',
        (tester) async {
      final deps = AccountTestDeps();
      deps.auth.failNext['requestEmailChange'] =
          const AuthFailure('email already registered', status: 409);
      await openSheet(tester, deps);
      await typeInto(tester, 'email_change_input', 'taken@example.com');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pump();
      expect(find.text('email already registered'), findsOneWidget);

      await tester.tapAt(const Offset(180, 20));
      await tester.pumpAndSettle();
      expect(find.byType(EmailChangeSheet), findsOneWidget);

      await tester.tap(find.byKey(const Key('email_change_close')));
      await tester.pumpAndSettle();
      expect(find.byType(EmailChangeSheet), findsNothing);
    });
  });

  group('security (2FA)', () {
    Finder switchFinder() => find.descendant(
        of: find.byKey(const Key('two_factor_switch')),
        matching: find.byType(Switch));

    testWidgets('turning off: confirm, then password; cancel does nothing',
        (tester) async {
      final deps = AccountTestDeps();
      await _open(tester, deps, const SecurityPage());
      await tester.tap(switchFinder());
      await tester.pumpAndSettle();
      expect(find.text('Turn off 2-step verification?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('two_factor_off_cancel')));
      await tester.pumpAndSettle();
      expect(deps.auth.twoFactorCalls, isEmpty);

      await tester.tap(switchFinder());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('two_factor_off_confirm')));
      await tester.pumpAndSettle();
      // Outside tap does not close the password dialog.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('two_factor_password')), findsOneWidget);
      await tester.tap(find.byKey(const Key('two_factor_password_confirm')));
      await tester.pump();
      expect(find.text('Enter your password'), findsOneWidget);

      await typeInto(tester, 'two_factor_password', 'secret-pass');
      await tester.tap(find.byKey(const Key('two_factor_password_confirm')));
      await tester.pumpAndSettle();
      expect(deps.auth.twoFactorCalls, [(false, 'secret-pass')]);
      expect(find.text('2-step verification is off.'), findsOneWidget);
      expect(tester.widget<Switch>(switchFinder()).value, isFalse);
    });

    for (final (status, key, text) in [
      (401, 'two_factor_password_error', "That password isn't right."),
      (
        429,
        'two_factor_lockout',
        'too many attempts. Please try again in 60 seconds.'
      ),
    ]) {
      testWidgets('password dialog error [$status]', (tester) async {
        final deps = AccountTestDeps();
        deps.auth.failNext['toggleTwoFactor'] = AuthFailure(
            status == 401
                ? 'Incorrect login details.'
                : 'too many attempts. Please try again in 60 seconds.',
            status: status);
        await _open(tester, deps, const SecurityPage());
        await tester.tap(switchFinder());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('two_factor_off_confirm')));
        await tester.pumpAndSettle();
        await typeInto(tester, 'two_factor_password', 'wrong');
        await tester.tap(find.byKey(const Key('two_factor_password_confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(Key(key)), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.byKey(const Key('two_factor_password')), findsOneWidget);
      });
    }

    testWidgets('turning on: switch locked during the request', (tester) async {
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(user: FakeAuthFlow.customer(twoFactor: false)));
      deps.auth.gates['toggleTwoFactor'] = Completer<void>();
      await _open(tester, deps, const SecurityPage());
      await tester.tap(switchFinder());
      await tester.pump();
      expect(find.byKey(const Key('two_factor_busy')), findsOneWidget);
      deps.auth.gates.remove('toggleTwoFactor')!.complete();
      await tester.pumpAndSettle();
      expect(deps.auth.twoFactorCalls, [(true, null)]);
      expect(find.text('2-step verification is on.'), findsOneWidget);
      expect(tester.widget<Switch>(switchFinder()).value, isTrue);
    });
  });
}
