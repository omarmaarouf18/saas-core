import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/feature_flags.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/screens/login_screen.dart';
import 'package:frontend/screens/settings_screen.dart';

import '../customer/customer_harness.dart';

void main() {
  test('both redesign flags are off by default', () {
    expect(kRedesignCustomer, isFalse);
    expect(kRedesignAuth, isFalse);
  });

  testWidgets('QD_REDESIGN_CUSTOMER on: the Account tab is AccountPage',
      (tester) async {
    usePhone(tester);
    await tester
        .pumpWidget(customerApp(CustomerTestDeps(), const CustomerShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byKey(const Key('customer_shell_nav')),
        matching: find.text('Account')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('flags off: signed out HomeScreen falls back to LoginScreen',
      (tester) async {
    // Default test viewport: the old LoginScreen overflows at 360 dp with
    // the test font (pre-existing, not part of this task).
    final deps = CustomerTestDeps()..auth.user = null;
    await tester.pumpWidget(customerApp(deps, const HomeScreen()));
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
