import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/owner/owner_shell.dart';
import 'package:frontend/features/verification/verification_page.dart';
import 'package:frontend/screens/settings_screen.dart';

import 'owner_harness.dart';

void main() {
  group('OwnerShell', () {
    OwnerTestDeps deps0() {
      final deps = OwnerTestDeps();
      deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
      deps.owner.nextJobs = [ownerJob(requestStatus: 'pending')];
      return deps;
    }

    Future<void> pumpShell(WidgetTester tester, OwnerTestDeps deps) async {
      await tester.pumpWidget(
          ownerApp(deps, OwnerShell(now: () => ownerNow), withData: false));
      await tester.pumpAndSettle();
    }

    testWidgets('loads once on open and shows Today with four tabs',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      expect(deps.owner.jobCalls, 1);
      expect(deps.owner.employeeCalls, 1);
      expect(deps.auth.profileCalls, 1);
      expect(find.byKey(const Key('own_today_page')), findsOneWidget);
      for (final label in ['Today', 'Orders', 'Team', 'Account']) {
        expect(
            find.descendant(
                of: find.byKey(const Key('owner_shell_nav')),
                matching: find.text(label)),
            findsOneWidget);
      }
    });

    testWidgets('tabs switch pages and refresh the data', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      Finder nav(String label) => find.descendant(
          of: find.byKey(const Key('owner_shell_nav')),
          matching: find.text(label));

      await tester.tap(nav('Orders'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_orders_page')), findsOneWidget);
      expect(find.byKey(const Key('own_order_a1b2c3d4e5f6')), findsOneWidget);
      expect(deps.owner.jobCalls, 2);

      await tester.tap(nav('Team'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_team_page')), findsOneWidget);
      expect(find.text('Karim'), findsOneWidget);
    });

    testWidgets('Today "All" opens the Team tab; orders link the Orders tab',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_team_page')), findsOneWidget);
    });

    testWidgets('a page pushed from a tab gets the shell data', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      await tester.tap(find.text('Respond'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_cancel_request')), findsOneWidget);
    });

    testWidgets('Account is the account page with the owner rows',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      expect(find.byType(AccountPage), findsNothing); // built lazily
      await tester.tap(find.descendant(
          of: find.byKey(const Key('owner_shell_nav')),
          matching: find.text('Account')));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
      for (final (row, opened) in [
        ('account_service_setup', 'service_setup'),
        ('account_plan', 'subscription'),
        ('account_wallet', 'wallet'),
        ('account_activity', 'history'),
      ]) {
        await tester.tap(find.byKey(Key(row)));
        await tester.pumpAndSettle();
        expect(deps.nav.opened.last, opened, reason: row);
      }
      // Verification opens the shared page.
      await tester.tap(find.byKey(const Key('account_verification')));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationPage), findsOneWidget);
    });

    testWidgets('Account tab loads the plan each time it opens',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextWallet =
          (total: 0, escrow: 0, withdrawable: 0, tier: 'paid');
      await pumpShell(tester, deps);
      expect(deps.owner.dashboardCalls, isEmpty);
      Finder tab(String label) => find.descendant(
          of: find.byKey(const Key('owner_shell_nav')),
          matching: find.text(label));
      await tester.tap(tab('Account'));
      await tester.pumpAndSettle();
      expect(deps.owner.dashboardCalls, ['owner-jwt']);
      expect(
          find.descendant(
              of: find.byKey(const Key('account_plan')),
              matching: find.text('Paid')),
          findsOneWidget);
      await tester.tap(tab('Today'));
      await tester.pumpAndSettle();
      await tester.tap(tab('Account'));
      await tester.pumpAndSettle();
      expect(deps.owner.dashboardCalls, ['owner-jwt', 'owner-jwt']);
    });

    testWidgets('opening on the Account tab loads the plan', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await tester.pumpWidget(ownerApp(
          deps, OwnerShell(initialIndex: 3, now: () => ownerNow),
          withData: false));
      await tester.pumpAndSettle();
      expect(deps.owner.dashboardCalls, ['owner-jwt']);
    });

    testWidgets('bell opens the existing notifications screen', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpShell(tester, deps);
      await tester.tap(find.byKey(const Key('own_today_bell')));
      expect(deps.nav.opened, ['notifications']);
    });
  });
}
