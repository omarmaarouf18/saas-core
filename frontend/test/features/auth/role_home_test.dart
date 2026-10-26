import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/auth/login_page.dart';
import 'package:frontend/features/auth/role_home.dart';
import 'package:frontend/features/auth/unsupported_role_page.dart';
import 'package:frontend/features/courier/courier_shell.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/features/owner/owner_shell.dart';

import '../courier/courier_harness.dart' as courier;
import '../customer/customer_harness.dart' as customer;
import '../owner/owner_harness.dart' as owner;
import 'auth_harness.dart';

/// FE-CLEANUP item 3: with the QD_REDESIGN_* flags gone, every role goes
/// straight to its redesigned shell.
void main() {
  testWidgets('customer (role user): CustomerShell, Account is AccountPage',
      (tester) async {
    customer.usePhone(tester);
    await tester.pumpWidget(
        customer.customerApp(customer.CustomerTestDeps(), const RoleHome()));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerShell), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const Key('customer_shell_nav')),
        matching: find.text('Account')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
  });

  testWidgets('owner: OwnerShell', (tester) async {
    owner.usePhone(tester);
    await tester.pumpWidget(owner
        .ownerApp(owner.OwnerTestDeps(), const RoleHome(), withData: false));
    await tester.pumpAndSettle();
    expect(find.byType(OwnerShell), findsOneWidget);
  });

  testWidgets('courier (role employee): CourierShell; profile refreshed once',
      (tester) async {
    courier.usePhone(tester);
    final deps = courier.CourierTestDeps();
    await tester.pumpWidget(
        courier.courierApp(deps, const RoleHome(), withController: false));
    await tester.pumpAndSettle();
    expect(find.byType(CourierShell), findsOneWidget);
    expect(deps.auth.profileCalls, 1);
  });

  testWidgets('another role: the unsupported-role page', (tester) async {
    usePhone(tester);
    final deps = AuthTestDeps(
        auth: FakeAuthFlow(
            user: FakeAuthFlow.customer(role: 'admin'), token: 'jwt'));
    await tester.pumpWidget(authApp(deps, const RoleHome()));
    await tester.pumpAndSettle();
    expect(find.byType(UnsupportedRolePage), findsOneWidget);
  });

  testWidgets('no user: the sign-in page', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(authApp(AuthTestDeps(), const RoleHome()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
