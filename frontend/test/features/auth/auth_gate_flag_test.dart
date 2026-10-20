import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/feature_flags.dart';
import 'package:frontend/features/auth/auth_gate.dart';
import 'package:frontend/features/auth/auth_nav.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/features/auth/otp_page.dart';
import 'package:frontend/screens/login_screen.dart';

import 'auth_harness.dart';

void main() {
  group('QD_REDESIGN_AUTH', () {
    test('is off by default', () {
      expect(kRedesignAuth, isFalse);
    });

    test('signedOutRootScreen picks the screen from the flag', () {
      expect(signedOutRootScreen(), isA<LoginScreen>());
      expect(signedOutRootScreen(redesign: false), isA<LoginScreen>());
      expect(signedOutRootScreen(redesign: true), isA<LoginPage>());
    });
  });

  group('RedesignAuthGate', () {
    const splashKey = Key('splash');

    testWidgets('splash during the first restore, then sign in',
        (tester) async {
      usePhone(tester);
      final deps = AuthTestDeps()
        ..auth.isRestoringSession = true
        ..auth.isLoading = true;
      await tester.pumpWidget(authApp(
          deps, const RedesignAuthGate(splash: SizedBox(key: splashKey))));
      expect(find.byKey(splashKey), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);

      deps.auth
        ..isRestoringSession = false
        ..isLoading = false
        ..notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });

    testWidgets(
        'a sign-in request keeps the page mounted and reaches the '
        'code page (the old gate unmounts it)', (tester) async {
      usePhone(tester);
      final deps = AuthTestDeps();
      deps.auth.gates['login'] = Completer<void>();
      await tester.pumpWidget(authApp(
          deps, const RedesignAuthGate(splash: SizedBox(key: splashKey))));
      await tester.pumpAndSettle();
      await typeInto(tester, 'login_email', 'mona@example.com');
      await typeInto(tester, 'login_password', 'secret-pass');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(deps.auth.isLoading, isTrue);
      expect(find.byKey(splashKey), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);

      deps.auth.gates.remove('login')!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(OtpPage), findsOneWidget);
      await tester.pump(const Duration(seconds: 60));
    });
  });
}
