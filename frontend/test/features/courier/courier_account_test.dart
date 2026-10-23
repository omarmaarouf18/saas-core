import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/models/user_profile.dart';

import '../account/account_harness.dart';

UserProfile _courier({String? kye}) => UserProfile(
      id: 'emp-1',
      email: 'karim@example.com',
      username: 'Karim',
      role: 'employee',
      kyeStatus: kye,
    );

// FE-COURIER item 6: the account page with the courier rows.
void main() {
  testWidgets('courier rows: verification, details, security, app, support',
      (tester) async {
    final deps =
        AccountTestDeps(auth: FakeAuthFlow(user: _courier(kye: 'approved')));
    await pumpAccount(tester, deps, const AccountPage());
    expect(find.text('Karim'), findsOneWidget);
    for (final key in [
      'account_verification',
      'account_details',
      'account_security',
      'account_language',
      'account_theme',
      'account_support',
      'account_sign_out',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.text('Verified'), findsOneWidget);
    // Customer-only rows.
    expect(find.byKey(const Key('account_addresses')), findsNothing);
    expect(find.byKey(const Key('account_notifications')), findsNothing);

    await tester.tap(find.byKey(const Key('account_verification')));
    expect(deps.accountNav.verification, 1);
  });

  for (final (kye, label) in [
    (null, 'Not uploaded'),
    ('pending_super_admin_approval', 'Under review'),
    ('rejected', 'Not accepted'),
  ]) {
    testWidgets('verification value [$kye]', (tester) async {
      await pumpAccount(
          tester,
          AccountTestDeps(auth: FakeAuthFlow(user: _courier(kye: kye))),
          const AccountPage());
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('customers keep their rows and no verification row',
      (tester) async {
    await pumpAccount(tester, AccountTestDeps(), const AccountPage());
    expect(find.byKey(const Key('account_verification')), findsNothing);
    expect(find.byKey(const Key('account_addresses')), findsOneWidget);
    expect(find.byKey(const Key('account_notifications')), findsOneWidget);
  });
}
