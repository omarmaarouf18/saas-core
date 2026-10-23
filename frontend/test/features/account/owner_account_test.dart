import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/models/user_profile.dart';

import 'account_harness.dart';

UserProfile _owner({String? kyb}) => UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'Nile Express',
      role: 'owner',
      kycStatus: kyb,
    );

/// Records the owner rows' hand-offs.
class _Links {
  final List<String> opened = [];

  OwnerAccountLinks links({String? plan}) => OwnerAccountLinks(
        openServiceSetup: (_) => opened.add('service_setup'),
        openPlan: (_) => opened.add('plan'),
        openWallet: (_) => opened.add('wallet'),
        openActivity: (_) => opened.add('activity'),
        planValue: plan,
      );
}

// FE-OWNER-2b item 5: the account page with the owner rows.
void main() {
  testWidgets('owner rows first, then the shared rows', (tester) async {
    final links = _Links();
    final deps =
        AccountTestDeps(auth: FakeAuthFlow(user: _owner(kyb: 'approved')));
    await pumpAccount(
        tester, deps, AccountPage(owner: links.links(plan: 'Paid')));
    expect(find.text('Your business'), findsOneWidget);
    for (final key in [
      'account_verification',
      'account_service_setup',
      'account_plan',
      'account_wallet',
      'account_activity',
      'account_details',
      'account_security',
      'account_language',
      'account_theme',
      'account_support',
      'account_sign_out',
    ]) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // Customer-only rows.
    expect(find.byKey(const Key('account_addresses')), findsNothing);
    expect(find.byKey(const Key('account_notifications')), findsNothing);
    // Profile re-fetched on open (KYB status is fresh).
    expect(deps.auth.calls, contains('fetchUserProfile:'));
  });

  testWidgets('owner rows open their pages', (tester) async {
    final links = _Links();
    final deps = AccountTestDeps(auth: FakeAuthFlow(user: _owner()));
    await pumpAccount(tester, deps, AccountPage(owner: links.links()));
    for (final key in [
      'account_service_setup',
      'account_plan',
      'account_wallet',
      'account_activity',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }
    expect(links.opened, ['service_setup', 'plan', 'wallet', 'activity']);
    await tester.tap(find.byKey(const Key('account_verification')));
    expect(deps.accountNav.verification, 1);
  });

  testWidgets('plan value only when known', (tester) async {
    await pumpAccount(
        tester,
        AccountTestDeps(auth: FakeAuthFlow(user: _owner())),
        AccountPage(owner: _Links().links(plan: 'Free')));
    expect(find.text('Free'), findsOneWidget);
  });

  for (final (kyb, label) in [
    (null, 'Not uploaded'),
    ('pending_super_admin_approval', 'Under review'),
    ('rejected', 'Not accepted'),
    ('approved', 'Verified'),
  ]) {
    testWidgets('KYB value [$kyb]', (tester) async {
      await pumpAccount(
          tester,
          AccountTestDeps(auth: FakeAuthFlow(user: _owner(kyb: kyb))),
          AccountPage(owner: _Links().links()));
      expect(
          find.descendant(
              of: find.byKey(const Key('account_verification')),
              matching: find.text(label)),
          findsOneWidget);
    });
  }

  testWidgets('owner without links: no business rows, no customer rows',
      (tester) async {
    await pumpAccount(
        tester,
        AccountTestDeps(auth: FakeAuthFlow(user: _owner())),
        const AccountPage());
    expect(find.text('Your business'), findsNothing);
    expect(find.byKey(const Key('account_addresses')), findsNothing);
    expect(find.byKey(const Key('account_details')), findsOneWidget);
  });

  testWidgets('sign out', (tester) async {
    final deps = AccountTestDeps(auth: FakeAuthFlow(user: _owner()));
    await pumpAccount(tester, deps, AccountPage(owner: _Links().links()));
    await tester.scrollUntilVisible(
        find.byKey(const Key('account_sign_out')), 100);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account_sign_out')));
    await tester.pumpAndSettle();
    expect(deps.auth.calls, contains('logout:'));
    expect(deps.notifications.unsubscribes, 1);
    expect(deps.nav.signedOut, 1);
  });

  testWidgets('Arabic renders without overflow', (tester) async {
    await pumpAccount(
        tester,
        AccountTestDeps(auth: FakeAuthFlow(user: _owner(kyb: 'rejected'))),
        AccountPage(owner: _Links().links(plan: 'مجانية')),
        locale: ar);
    expect(tester.takeException(), isNull);
    expect(find.text('شغلك'), findsOneWidget);
  });
}
