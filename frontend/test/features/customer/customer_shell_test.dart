import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'customer_harness.dart';

void main() {
  testWidgets('three tabs; switching tabs refreshes orders', (tester) async {
    usePhone(tester);
    final deps = CustomerTestDeps();
    await tester.pumpWidget(customerApp(deps, const CustomerShell()));
    await tester.pumpAndSettle();
    final nav = find.byKey(const Key('customer_shell_nav'));
    expect(
        find.descendant(of: nav, matching: find.text('Home')), findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('My orders')),
        findsOneWidget);
    expect(find.descendant(of: nav, matching: find.text('Account')),
        findsOneWidget);
    expect(deps.marketplace.jobCalls, 1);

    await tester
        .tap(find.descendant(of: nav, matching: find.text('My orders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cust_orders_tabs')), findsOneWidget);
    expect(deps.marketplace.jobCalls, 2);
  });

  for (final dark in [false, true]) {
    testWidgets('shell uses the redesign theme [dark: $dark]', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(customerApp(
        CustomerTestDeps(),
        const CustomerShell(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      ));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byKey(const Key('cust_home_list')));
      expect(QdColors.of(ctx), dark ? QdColors.dark : QdColors.light);
      expect(tester.takeException(), isNull);
    });
  }
}
