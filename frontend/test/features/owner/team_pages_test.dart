import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/owner/employee_page.dart';
import 'package:frontend/features/owner/team_page.dart';

import 'owner_harness.dart';

void main() {
  OwnerTestDeps deps0() {
    final deps = OwnerTestDeps();
    deps.owner.nextEmployees = [
      staff('emp-1', 'Karim'),
      staff('emp-2', 'Sara'),
      staff('emp-3', 'Mahmoud', active: false),
    ];
    deps.owner.nextJobs = [
      ownerJob(id: 'run-000001', employeeId: 'emp-1', status: 'active'),
      ownerJob(id: 'done-00002', employeeId: 'emp-1', status: 'completed'),
      ownerJob(id: 'done-00003', employeeId: 'emp-2', status: 'completed'),
    ];
    return deps;
  }

  Widget team() => const Scaffold(body: OwnerTeamPage());

  group('team', () {
    testWidgets('roster with state chips and the current order',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, team());
      expect(find.text('All · 3'), findsOneWidget);
      expect(find.text('Karim'), findsOneWidget);
      expect(find.text('On a job'), findsOneWidget);
      expect(find.textContaining('#QD-RUN-0000'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('No order right now'), findsOneWidget);
      expect(find.text('Frozen'), findsNWidgets(2)); // tab + chip
      expect(find.text("Can't sign in or get orders"), findsOneWidget);
    });

    testWidgets('active / frozen filters', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, team());
      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('Mahmoud'), findsNothing);
      expect(find.text('Sara'), findsOneWidget);
      await tester.tap(find.text('Frozen').first);
      await tester.pumpAndSettle();
      expect(find.text('Mahmoud'), findsOneWidget);
      expect(find.text('Karim'), findsNothing);
    });

    testWidgets('"on the map" opens the old fleet map', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, team());
      await tester.tap(find.byKey(const Key('own_team_map')));
      expect(deps.nav.opened, ['fleet_map']);
    });

    testWidgets('error (fails closed) with retry; empty', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextEmployeesError = 'db down';
      await pumpOwner(tester, deps, team());
      expect(find.byKey(const Key('own_team_error')), findsOneWidget);
      deps.owner.nextEmployeesError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No couriers yet'), findsOneWidget);
    });

    testWidgets('add courier: validation, then success refreshes the team',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, team());
      await tester.tap(find.byKey(const Key('own_team_add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_add_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('own_add_submit')));
      await tester.pumpAndSettle();
      expect(deps.owner.registerCalls, isEmpty);

      await tester.enterText(find.byKey(const Key('own_add_username')), 'Omar');
      await tester.enterText(
          find.byKey(const Key('own_add_email')), 'omar@example.com');
      await tester.enterText(
          find.byKey(const Key('own_add_password')), 'short');
      await tester.tap(find.byKey(const Key('own_add_submit')));
      await tester.pumpAndSettle();
      expect(deps.owner.registerCalls, isEmpty); // SEC-03 length rule

      await tester.enterText(
          find.byKey(const Key('own_add_password')), 'long-enough-1');
      final before = deps.owner.employeeCalls;
      deps.owner.nextEmployees = [
        ...deps.owner.nextEmployees,
        staff('emp-new', 'Omar'),
      ];
      await tester.tap(find.byKey(const Key('own_add_submit')));
      await tester.pumpAndSettle();
      expect(deps.owner.registerCalls, [
        {
          'email': 'omar@example.com',
          'username': 'Omar',
          'password': 'long-enough-1',
          'ownerId': 'owner-1',
        }
      ]);
      expect(find.byKey(const Key('own_add_sheet')), findsNothing);
      expect(
          find.text('Omar was added. They can sign in now.'), findsOneWidget);
      expect(deps.owner.employeeCalls, before + 1);
      expect(find.text('All · 4'), findsOneWidget);
    });

    testWidgets('add courier: weak_password from the server is localized',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextRegisterError = ApiClientException(
          'password is too common',
          statusCode: 400,
          errorCode: 'weak_password');
      await pumpOwner(tester, deps, team());
      await tester.tap(find.byKey(const Key('own_team_add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('own_add_username')), 'Omar');
      await tester.enterText(
          find.byKey(const Key('own_add_email')), 'omar@example.com');
      await tester.enterText(
          find.byKey(const Key('own_add_password')), 'password123');
      await tester.tap(find.byKey(const Key('own_add_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_add_error')), findsOneWidget);
      // The localized SEC-03 copy, not the raw server text.
      expect(find.text(lookupOwnerEn().passwordTooCommon), findsOneWidget);
      expect(find.byKey(const Key('own_add_sheet')), findsOneWidget);
    });

    testWidgets('tap a courier opens their page', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, team());
      await tester.tap(find.byKey(const Key('own_courier_emp-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_employee_page')), findsOneWidget);
    });
  });

  group('employee page', () {
    Widget page(String id) => OwnerEmployeePage(employeeId: id);

    testWidgets('header, counts from loaded orders, current order',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, page('emp-1'));
      expect(find.text('Karim'), findsOneWidget);
      expect(find.text('karim@example.com'), findsOneWidget);
      expect(find.text('On a job'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('own_employee_orders_count')),
              matching: find.text('2')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('own_employee_delivered_count')),
              matching: find.text('1')),
          findsOneWidget);
      // No ID-check row: /auth/employees does not return kye_status.
      expect(find.byKey(const Key('own_employee_kye')), findsNothing);

      await tester.tap(find.byKey(const Key('own_employee_current')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_page')), findsOneWidget);
    });

    testWidgets('ID-check row when the payload carries kye_status',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextEmployees = [
        {...staff('emp-1', 'Karim'), 'kye_status': 'pending'},
      ];
      await pumpOwner(tester, deps, page('emp-1'));
      expect(find.text('Under review'), findsOneWidget);
    });

    testWidgets('all their orders: orders page filtered by name',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, page('emp-2'));
      expect(find.text('None'), findsOneWidget); // no current order
      await tester.tap(find.byKey(const Key('own_employee_all_orders')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_orders_page')), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_done-00003')), findsOneWidget);
      expect(find.byKey(const Key('own_order_done-00002')), findsNothing);
    });

    testWidgets('freeze: password sheet, request, frozen afterwards',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, page('emp-2'));
      await tester.tap(find.byKey(const Key('own_employee_freeze')));
      await tester.pumpAndSettle();
      expect(find.text("Freeze Sara's account?"), findsOneWidget);

      // Empty password: asked for, nothing sent.
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Type your password.'), findsOneWidget);
      expect(deps.owner.toggleCalls, isEmpty);

      await tester.enterText(
          find.byKey(const Key('own_password_input')), 'owner-secret');
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pumpAndSettle();
      expect(deps.owner.toggleCalls, [
        {
          'employeeEmail': 'sara@example.com',
          'ownerEmail': 'owner@example.com',
          'ownerPassword': 'owner-secret',
          'setActive': false,
        }
      ]);
      expect(find.text("Sara's account is frozen."), findsOneWidget);
      expect(find.byKey(const Key('own_employee_unfreeze')), findsOneWidget);
      expect(find.text('Frozen'), findsOneWidget);
    });

    testWidgets('freeze with a wrong password: inline error, sheet stays',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextToggleError =
          ApiClientException('invalid owner credentials', statusCode: 403);
      await pumpOwner(tester, deps, page('emp-2'));
      await tester.tap(find.byKey(const Key('own_employee_freeze')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('own_password_input')), 'wrong');
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pumpAndSettle();
      expect(find.text("That password isn't right."), findsOneWidget);
      expect(find.byKey(const Key('own_password_sheet')), findsOneWidget);
      expect(find.byKey(const Key('own_employee_freeze')), findsOneWidget);

      // Then the right one.
      deps.owner.nextToggleError = null;
      await tester.enterText(
          find.byKey(const Key('own_password_input')), 'right');
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_password_sheet')), findsNothing);
      expect(deps.owner.toggleCalls.last['ownerPassword'], 'right');
    });

    for (final (err, shown) in [
      (
        ApiClientException('failed to freeze employee account, please retry',
            statusCode: 503),
        null
      ),
      (
        ApiClientException('action blocked: owner KYC approval is pending',
            statusCode: 403),
        'Your business documents must be approved first.'
      ),
      (
        ApiClientException('upgrade_required', statusCode: 402),
        'Managing couriers needs a paid plan.'
      ),
    ]) {
      testWidgets('freeze failure ${err.statusCode}: banner in the sheet',
          (tester) async {
        usePhone(tester);
        final deps = deps0();
        deps.owner.nextToggleError = err;
        await pumpOwner(tester, deps, page('emp-2'));
        await tester.tap(find.byKey(const Key('own_employee_freeze')));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const Key('own_password_input')), 'pw');
        await tester.tap(find.byKey(const Key('own_password_confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('own_password_error')), findsOneWidget);
        if (shown != null) expect(find.text(shown), findsOneWidget);
      });
    }

    testWidgets('unfreeze a frozen courier', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, page('emp-3'));
      await tester.tap(find.byKey(const Key('own_employee_unfreeze')));
      await tester.pumpAndSettle();
      expect(find.text("Unfreeze Mahmoud's account?"), findsOneWidget);
      await tester.enterText(find.byKey(const Key('own_password_input')), 'pw');
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pumpAndSettle();
      expect(deps.owner.toggleCalls.single['setActive'], true);
      expect(find.text("Mahmoud's account is active again."), findsOneWidget);
      expect(find.byKey(const Key('own_employee_freeze')), findsOneWidget);
    });

    testWidgets('double tap during a toggle sends one request', (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.toggleGate = Completer<void>();
      await pumpOwner(tester, deps, page('emp-2'));
      await tester.tap(find.byKey(const Key('own_employee_freeze')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('own_password_input')), 'pw');
      await tester.tap(find.byKey(const Key('own_password_confirm')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('own_password_confirm')),
          warnIfMissed: false);
      await tester.pump();
      expect(deps.owner.toggleCalls.length, 1);
      deps.owner.toggleGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a courier who left the team', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, page('emp-gone'));
      expect(find.byKey(const Key('own_employee_missing')), findsOneWidget);
    });
  });
}
