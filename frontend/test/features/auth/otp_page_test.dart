import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/otp_page.dart';

import 'auth_harness.dart';

Future<void> _pump(WidgetTester tester, AuthTestDeps deps,
    {String? devOtp}) async {
  usePhone(tester);
  await tester.pumpWidget(
      authApp(deps, OtpPage(email: 'mona@example.com', devOtp: devOtp)));
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String code) =>
    tester.enterText(find.byKey(const Key('qd_otp_field')), code);

void main() {
  testWidgets('dev code is filled in with a banner; confirm signs in',
      (tester) async {
    final deps = AuthTestDeps();
    await _pump(tester, deps, devOtp: '654321');
    expect(find.text('Test mode: we filled in the code 654321 for you.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('otp_confirm')));
    await tester.pump();
    expect(deps.auth.calls, ['verifyOtp:mona@example.com|654321']);
    expect(deps.nav.homes, 1);
  });

  testWidgets('no dev code: no banner, boxes empty, incomplete code refused',
      (tester) async {
    final deps = AuthTestDeps();
    await _pump(tester, deps);
    expect(find.byKey(const Key('otp_dev_banner')), findsNothing);
    await _type(tester, '123');
    await tester.tap(find.byKey(const Key('otp_confirm')));
    await tester.pump();
    expect(find.text('Enter all 6 digits'), findsOneWidget);
    expect(deps.auth.calls, isEmpty);
  });

  testWidgets('a full code verifies on its own, once', (tester) async {
    final deps = AuthTestDeps();
    deps.auth.gates['verifyOtp'] = Completer<void>();
    await _pump(tester, deps);
    await _type(tester, '111222');
    await tester.pump();
    // A second completion while in flight is ignored.
    await _type(tester, '111223');
    await tester.pump();
    deps.auth.gates.remove('verifyOtp')!.complete();
    await tester.pump();
    expect(deps.auth.calls, ['verifyOtp:mona@example.com|111222']);
    expect(deps.nav.homes, 1);
  });

  testWidgets('wrong code: error banner with retry, boxes marked',
      (tester) async {
    final deps = AuthTestDeps();
    deps.auth.failNext['verifyOtp'] =
        const AuthFailure('invalid or expired OTP code', status: 401);
    await _pump(tester, deps);
    await _type(tester, '000000');
    await tester.pump();
    expect(find.byKey(const Key('otp_error')), findsOneWidget);
    expect(find.text('invalid or expired OTP code'), findsOneWidget);
    expect(deps.nav.homes, 0);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(deps.auth.calls.length, 2);
    expect(deps.nav.homes, 1);
  });

  testWidgets('resend waits 60 s, then sends, refills and restarts',
      (tester) async {
    final deps = AuthTestDeps()..auth.devOtp = '777888';
    await _pump(tester, deps, devOtp: '123456');
    expect(find.byKey(const Key('otp_resend')), findsNothing);
    expect(find.textContaining('1:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 18));
    expect(find.textContaining('0:42'), findsOneWidget);
    expect(find.byKey(const Key('otp_resend')), findsNothing);

    await tester.pump(const Duration(seconds: 42));
    expect(find.byKey(const Key('otp_resend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('otp_resend')));
    await tester.pump();
    expect(deps.auth.calls, ['resendOtp:mona@example.com']);
    expect(find.text('We sent you a new code.'), findsOneWidget);
    expect(find.text('Test mode: we filled in the code 777888 for you.'),
        findsOneWidget);
    expect(find.byKey(const Key('otp_resend')), findsNothing);
    expect(find.textContaining('1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('resend failure: its own banner, retry resends', (tester) async {
    final deps = AuthTestDeps();
    deps.auth.failNext['resendOtp'] = const AuthFailure(
        'too many attempts for this email. Please try again in 60 seconds.',
        status: 429);
    await _pump(tester, deps);
    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.byKey(const Key('otp_resend')));
    await tester.pump();
    expect(find.byKey(const Key('otp_resend_error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(deps.auth.calls, [
      'resendOtp:mona@example.com',
      'resendOtp:mona@example.com',
    ]);
    expect(find.byKey(const Key('otp_resend_error')), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('Arabic: email and code stay left to right', (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps();
    await tester.pumpWidget(authApp(
        deps, const OtpPage(email: 'mona@example.com', devOtp: '123456'),
        locale: ar));
    await tester.pump();
    expect(find.text('اكتب الكود'), findsOneWidget);
    expect(tester.getCenter(find.text('1')).dx,
        lessThan(tester.getCenter(find.text('6')).dx));
    await tester.pump(const Duration(seconds: 60));
  });
}
