import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/account/my_details_page.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/features/account/security_page.dart';

import 'account_harness.dart';

void main() {
  testWidgets('header, rows and their values; profile refreshed on open',
      (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage());
    expect(deps.auth.calls, ['fetchUserProfile:']);
    expect(find.text('Mona'), findsOneWidget);
    expect(find.text('mona@example.com'), findsOneWidget);
    expect(find.text('2-step verification on'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // saved addresses
    expect(find.text('Same as the phone'), findsOneWidget); // language
    expect(find.text('Light'), findsOneWidget); // theme
    // FE-OWNER-1 item 0: no wallet "coming soon" row for customers.
    expect(find.byKey(const Key('account_wallet')), findsNothing);
    expect(find.text('Soon'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.byKey(const Key('account_suspended')), findsNothing);
  });

  testWidgets('load error banner with retry', (tester) async {
    final deps = AccountTestDeps();
    deps.auth.failNext['fetchUserProfile'] =
        const AuthFailure('Couldn\'t connect.');
    await pumpAccount(tester, deps, const AccountPage());
    expect(find.byKey(const Key('account_load_error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(deps.auth.calls.length, 2);
    expect(find.byKey(const Key('account_load_error')), findsNothing);
  });

  for (final (reason, shown) in [
    ('Unpaid fees', 'Unpaid fees'),
    (
      null,
      "You can't change your details for now. Contact support to know more."
    )
  ]) {
    testWidgets('suspension banner [reason: $reason]', (tester) async {
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(
              user: FakeAuthFlow.customer(
                  accountStatus: 'suspended', suspensionReason: reason)));
      await pumpAccount(tester, deps, const AccountPage());
      expect(find.text('Your account is suspended'), findsOneWidget);
      expect(find.text(shown), findsOneWidget);
    });
  }

  testWidgets('language: Arabic, then back to the phone setting',
      (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage());
    await tester.tap(find.byKey(const Key('account_language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choice_العربية')));
    await tester.pumpAndSettle();
    expect(deps.locale.set, [ar]);
    expect(find.text('اللغة'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account_language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choice_زي الموبايل')));
    await tester.pumpAndSettle();
    expect(deps.locale.set, [ar, null]);
  });

  testWidgets('theme: dark', (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage());
    await tester.tap(find.byKey(const Key('account_theme')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choice_Dark')));
    await tester.pumpAndSettle();
    expect(deps.theme.themeMode, ThemeMode.dark);
    expect(find.text('Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows open their pages; notifications and support hand off',
      (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage());
    for (final (key, type) in [
      ('account_details', MyDetailsPage),
      ('account_edit', MyDetailsPage),
      ('account_addresses', SavedAddressesPage),
      ('account_security', SecurityPage),
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(find.byType(type), findsOneWidget, reason: key);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('account_notifications')));
    await tester.scrollUntilVisible(
        find.byKey(const Key('account_support')), 100);
    await tester.tap(find.byKey(const Key('account_support')));
    await tester.pumpAndSettle();
    expect(deps.accountNav.notifications, 1);
    expect(deps.accountNav.support, 1);
  });

  testWidgets('sign out: stream closed, session revoked, signed-out screen',
      (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage());
    await tester.scrollUntilVisible(
        find.byKey(const Key('account_sign_out')), 100);
    await tester.tap(find.byKey(const Key('account_sign_out')));
    await tester.pumpAndSettle();
    expect(deps.notifications.unsubscribes, 1);
    expect(deps.auth.calls.last, 'logout:');
    expect(deps.nav.signedOut, 1);
  });

  testWidgets('Arabic layout builds without overflow', (tester) async {
    final deps = AccountTestDeps();
    await pumpAccount(tester, deps, const AccountPage(), locale: ar);
    expect(find.text('التحقق بخطوتين شغال'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
