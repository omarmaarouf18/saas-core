import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/app_client.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/features/auth/otp_page.dart';
import 'package:frontend/features/auth/role_home.dart';
import 'package:frontend/features/auth/signup_page.dart';
import 'package:frontend/features/auth/unsupported_role_page.dart';
import 'package:frontend/features/courier/courier_shell.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/features/owner/owner_shell.dart';

import '../courier/courier_harness.dart' as courier;
import '../customer/customer_harness.dart' as customer;
import '../owner/owner_harness.dart' as owner;
import 'auth_harness.dart';

/// SPLIT-APPS (ADR-0030): three apps from one codebase. Each app lets its
/// own role into its shell, shows every other role a page naming the right
/// app (never another role's shell), and signs up only its own role; the
/// employees app has no sign-up at all.
void main() {
  tearDown(() => AppClient.debugOverride = null);

  const roleOf = {
    AppClient.customer: 'user',
    AppClient.console: 'owner',
    AppClient.employees: 'employee',
  };

  group('allowed role lands on its shell', () {
    testWidgets('Waddify: customer → CustomerShell', (tester) async {
      AppClient.debugOverride = AppClient.customer;
      customer.usePhone(tester);
      await tester.pumpWidget(
          customer.customerApp(customer.CustomerTestDeps(), const RoleHome()));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerShell), findsOneWidget);
      expect(find.byType(UnsupportedRolePage), findsNothing);
    });

    testWidgets('Waddify Console: owner → OwnerShell', (tester) async {
      AppClient.debugOverride = AppClient.console;
      owner.usePhone(tester);
      await tester.pumpWidget(owner
          .ownerApp(owner.OwnerTestDeps(), const RoleHome(), withData: false));
      await tester.pumpAndSettle();
      expect(find.byType(OwnerShell), findsOneWidget);
      expect(find.byType(UnsupportedRolePage), findsNothing);
    });

    testWidgets('Waddify Employees: employee → CourierShell', (tester) async {
      AppClient.debugOverride = AppClient.employees;
      courier.usePhone(tester);
      await tester.pumpWidget(courier.courierApp(
          courier.CourierTestDeps(), const RoleHome(),
          withController: false));
      await tester.pumpAndSettle();
      expect(find.byType(CourierShell), findsOneWidget);
      expect(find.byType(UnsupportedRolePage), findsNothing);
    });
  });

  group('another role sees the wrong-app page', () {
    for (final app in AppClient.values) {
      for (final MapEntry(key: rightApp, value: role) in roleOf.entries) {
        if (rightApp == app) continue;
        testWidgets('${app.displayName}: $role → names ${rightApp.displayName}',
            (tester) async {
          AppClient.debugOverride = app;
          usePhone(tester);
          final deps = AuthTestDeps(
              auth: FakeAuthFlow(
                  user: FakeAuthFlow.customer(role: role), token: 'jwt'));
          await tester.pumpWidget(authApp(deps, const RoleHome()));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('wrong_app_page')), findsOneWidget);
          expect(find.text('This account is for another app'), findsOneWidget);
          expect(
              find.text('Your account works in ${rightApp.displayName}. '
                  'Install ${rightApp.displayName} and sign in there.'),
              findsOneWidget);
          expect(find.byType(CustomerShell), findsNothing);
          expect(find.byType(OwnerShell), findsNothing);
          expect(find.byType(CourierShell), findsNothing);

          await tester.tap(find.byKey(const Key('unsupported_role_sign_out')));
          await tester.pumpAndSettle();
          expect(deps.auth.calls, contains('logout:'));
          expect(deps.nav.signedOut, 1);
        });
      }
    }

    testWidgets('Arabic names the right app too', (tester) async {
      AppClient.debugOverride = AppClient.customer;
      usePhone(tester);
      final deps = AuthTestDeps(
          auth: FakeAuthFlow(
              user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt'));
      await tester.pumpWidget(authApp(deps, const RoleHome(), locale: ar));
      await tester.pumpAndSettle();
      expect(find.text('الحساب ده لتطبيق تاني'), findsOneWidget);
      expect(find.textContaining('Waddify Console'), findsOneWidget);
    });

    for (final app in AppClient.values) {
      testWidgets('${app.displayName}: a staff role keeps the web-console page',
          (tester) async {
        AppClient.debugOverride = app;
        usePhone(tester);
        final deps = AuthTestDeps(
            auth: FakeAuthFlow(
                user: FakeAuthFlow.customer(role: 'admin'), token: 'jwt'));
        await tester.pumpWidget(authApp(deps, const RoleHome()));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsupported_role_page')), findsOneWidget);
        expect(find.byKey(const Key('wrong_app_page')), findsNothing);
      });
    }
  });

  group('sign-up per app', () {
    testWidgets('Waddify Employees: no sign-up link; staff note instead',
        (tester) async {
      AppClient.debugOverride = AppClient.employees;
      usePhone(tester);
      await tester.pumpWidget(authApp(AuthTestDeps(), const LoginPage()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_to_signup')), findsNothing);
      expect(find.text('Create one'), findsNothing);
      expect(find.byKey(const Key('login_staff_note')), findsOneWidget);
      expect(
          find.text('Staff accounts are created by your company. '
              'Ask your manager for your sign-in details.'),
          findsOneWidget);
    });

    for (final (app, role) in [
      (AppClient.customer, 'user'),
      (AppClient.console, 'owner'),
    ]) {
      testWidgets(
          '${app.displayName}: login links to sign-up, which creates '
          '"$role"', (tester) async {
        AppClient.debugOverride = app;
        usePhone(tester);
        final deps = AuthTestDeps();
        await tester.pumpWidget(authApp(deps, const LoginPage()));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('login_staff_note')), findsNothing);
        await tester.tap(find.text('Create one'));
        await tester.pumpAndSettle();
        expect(find.byType(SignupPage), findsOneWidget);
        expect(find.byKey(const Key('signup_role_customer')), findsNothing);
        expect(find.byKey(const Key('signup_role_owner')), findsNothing);

        await typeInto(tester, 'signup_name', 'Mona Ali');
        await typeInto(tester, 'signup_email', 'mona@example.com');
        await typeInto(tester, 'signup_password', 'long-enough-1');
        await tester.tap(find.byKey(const Key('signup_submit')));
        await tester.pumpAndSettle();
        expect(deps.auth.calls, ['signup:mona@example.com|Mona Ali|$role']);
        expect(find.byType(OtpPage), findsOneWidget);
      });
    }
  });
}
