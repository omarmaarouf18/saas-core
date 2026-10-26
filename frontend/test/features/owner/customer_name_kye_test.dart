import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/order_detail_page.dart';
import 'package:frontend/features/owner/orders_page.dart';
import 'package:frontend/features/owner/owner_rules.dart';
import 'package:frontend/features/owner/team_page.dart';
import 'package:frontend/features/owner/today_page.dart';

import 'owner_harness.dart';

const _lri = '\u2066';
const _pdi = '\u2069';

OwnerTestDeps _deps() {
  final deps = OwnerTestDeps();
  deps.owner.nextEmployees = [
    {...staff('emp-1', 'Karim'), 'kye_status': 'approved'},
    {...staff('emp-2', 'Sara'), 'kye_status': 'pending_super_admin_approval'},
    {...staff('emp-3', 'Hany'), 'kye_status': 'rejected'},
    {...staff('emp-4', 'Omar'), 'kye_status': 'none'},
  ];
  deps.owner.nextJobs = [
    ownerJob(
      id: 'named-0001',
      employeeId: 'emp-1',
      createdAt: ownerNow.subtract(const Duration(minutes: 30)),
      requestStatus: 'pending',
      requestReason: 'Flat tyre',
      requestedAt: ownerNow.subtract(const Duration(minutes: 5)),
    ),
    ownerJob(id: 'legacy-001', employeeId: 'emp-2', userId: 'cust-abcdef'),
  ];
  deps.owner.nextJobJson = {
    'named-0001': {'id': 'named-0001', 'customer_name': ' Mona Ali '},
    'legacy-001': {'id': 'legacy-001', 'customer_name': ''},
  };
  return deps;
}

void main() {
  group('rules', () {
    test('customer_name: trimmed, empty is none', () {
      expect(OwnerJobExtras.fromJson({'customer_name': ' Mona '}).customerName,
          'Mona');
      expect(OwnerJobExtras.fromJson({'customer_name': '  '}).customerName,
          isNull);
      expect(OwnerJobExtras.fromJson({}).customerName, isNull);
      expect(OwnerJobExtras.fromJson(null).customerName, isNull);
    });

    test('kye_status → state', () {
      expect(kyeStateOf('approved'), KyeState.approved);
      expect(kyeStateOf('pending_super_admin_approval'), KyeState.pending);
      expect(kyeStateOf('pending'), KyeState.pending);
      expect(kyeStateOf(' Rejected '), KyeState.rejected);
      expect(kyeStateOf('none'), KyeState.none);
      expect(kyeStateOf(''), KyeState.none);
      expect(kyeStateOf(null), KyeState.none);
      expect(kyeStateOf('something_new'), KyeState.none);
    });
  });

  group('customer_name', () {
    testWidgets('orders list: name first; old jobs keep ref · courier',
        (tester) async {
      usePhone(tester);
      final deps = _deps();
      await pumpOwner(tester, deps, const Scaffold(body: OwnerOrdersPage()));
      expect(find.text('Mona Ali · $_lri#QD-NAMED-00$_pdi'), findsOneWidget);
      // The courier moves to the summary line.
      expect(find.textContaining('Karim · '), findsOneWidget);
      expect(find.text('$_lri#QD-LEGACY-0$_pdi · Sara'), findsOneWidget);

      // Search finds the customer by name.
      await tester.enterText(find.byType(TextField), 'mona');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_named-0001')), findsOneWidget);
      expect(find.byKey(const Key('own_order_legacy-001')), findsNothing);
    });

    testWidgets('order detail: the name, else "Customer #ref"', (tester) async {
      usePhone(tester);
      final deps = _deps();
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'named-0001'));
      expect(find.text('Mona Ali'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpOwner(
          tester, deps, const OwnerOrderDetailPage(jobId: 'legacy-001'));
      expect(find.text('Customer $_lri#cust-a$_pdi'), findsOneWidget);
    });

    testWidgets('Today: the request row names the customer', (tester) async {
      usePhone(tester);
      final deps = _deps();
      await pumpOwner(
          tester,
          deps,
          Scaffold(
              body: OwnerTodayPage(onShowTeam: () {}, onShowOrders: () {})));
      expect(find.textContaining('For Mona Ali · '), findsOneWidget);
    });
  });

  group('KYE chips', () {
    testWidgets('team list: one chip per courier, verification wording',
        (tester) async {
      usePhone(tester);
      final deps = _deps();
      await pumpOwner(tester, deps, const Scaffold(body: OwnerTeamPage()));
      Finder chip(String id, String text) => find.descendant(
          of: find.byKey(Key('own_courier_kye_$id')),
          matching: find.text(text));
      expect(chip('emp-1', 'Verified'), findsOneWidget);
      expect(chip('emp-2', 'Under review'), findsOneWidget);
      expect(chip('emp-3', 'Not accepted'), findsOneWidget);
      expect(chip('emp-4', 'Not uploaded'), findsOneWidget);
    });

    testWidgets('tap the chip → the member page with its verification',
        (tester) async {
      usePhone(tester);
      final deps = _deps();
      await pumpOwner(tester, deps, const Scaffold(body: OwnerTeamPage()));
      await tester.tap(find.byKey(const Key('own_courier_kye_emp-3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_kye_sheet')), findsOneWidget);
      expect(
          find.text("Hany's documents weren't accepted. They can upload new "
              'ones from Verification in the courier app.'),
          findsOneWidget);
      await tester.tapAt(const Offset(180, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_employee_kye')), findsOneWidget);
    });
  });
}
