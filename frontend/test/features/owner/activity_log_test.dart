import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/activity_log_page.dart';
import 'package:frontend/features/owner/activity_rules.dart';

import 'owner_harness.dart';

Map<String, dynamic> audit(String id, String action,
        {String? employeeId, Duration ago = const Duration(minutes: 10)}) =>
    {
      'id': id,
      'employee_id': employeeId ?? '',
      'tenant_id': 'owner-1',
      'action': action,
      'timestamp': ownerNow.subtract(ago).toUtc().toIso8601String(),
    };

Map<String, dynamic> ledger(String id, String type, num amount,
        {String jobId = '',
        num before = 0,
        num after = 0,
        Duration ago = const Duration(hours: 2)}) =>
    {
      'id': id,
      'job_id': jobId,
      'type': type,
      'amount': amount,
      'balance_before': before,
      'balance_after': after,
      'description': 'escrow lock for job $jobId',
      'timestamp': ownerNow.subtract(ago).toUtc().toIso8601String(),
    };

void main() {
  group('activity rules', () {
    test('money direction: balance change first, then the type', () {
      LedgerItem item(Map<String, dynamic> j) => LedgerItem.fromJson(j);
      expect(
          item(ledger('a', 'escrow_lock', 50, before: 100, after: 50)).incoming,
          isFalse);
      expect(item(ledger('b', 'payout', 40, before: 90, after: 50)).incoming,
          isFalse);
      expect(item(ledger('c', 'payout', 40)).incoming, isTrue);
      expect(item(ledger('d', 'escrow_release', 40)).incoming, isTrue);
      expect(item(ledger('e', 'platform_fee', 2)).incoming, isFalse);
      expect(item(ledger('f', 'payout_refund', 40)).incoming, isTrue);
      expect(item(ledger('g', 'deposit', 10, before: 0, after: 10)).incoming,
          isTrue);
      expect(item(ledger('h', 'deposit', 10)).hasBalance, isFalse);
    });

    test('periods use the device day', () {
      final now = DateTime(2026, 10, 19, 15, 30);
      expect(
          inPeriod(LogPeriod.today, DateTime(2026, 10, 19, 0, 1), now), isTrue);
      expect(inPeriod(LogPeriod.today, DateTime(2026, 10, 18, 23, 59), now),
          isFalse);
      expect(
          inPeriod(LogPeriod.week, DateTime(2026, 10, 13, 0, 0), now), isTrue);
      expect(inPeriod(LogPeriod.week, DateTime(2026, 10, 12, 23, 0), now),
          isFalse);
      expect(inPeriod(LogPeriod.all, null, now), isTrue);
      expect(inPeriod(LogPeriod.today, null, now), isFalse);
    });

    test('audit entries parse, blank employee id is none', () {
      final items = AuditItem.listFrom([
        audit('1', 'KYC_REVIEWED'),
        audit('2', 'Arrived at Pickup', employeeId: 'emp-1'),
        'garbage',
      ]);
      expect(items.map((e) => e.employeeId), [null, 'emp-1']);
    });
  });

  group('OwnerActivityPage', () {
    OwnerTestDeps deps0() {
      final deps = OwnerTestDeps();
      deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
      deps.owner.nextAudit = [
        audit('a1', 'Arrived at Pickup', employeeId: 'emp-1'),
        audit('a2', 'KYC_REVIEWED',
            employeeId: 'owner-1', ago: const Duration(days: 3)),
        audit('a3', 'ACCOUNT_SUSPENDED',
            employeeId: 'emp-gone99', ago: const Duration(days: 30)),
      ];
      deps.owner.nextLedger = [
        ledger('l1', 'escrow_lock', 120,
            jobId: 'b7c1d2e3f4a5', before: 500, after: 380),
        ledger('l2', 'payout', 120,
            jobId: 'b7c1d2e3f4a5', ago: const Duration(days: 2)),
      ];
      return deps;
    }

    Future<void> pumpPage(WidgetTester tester, OwnerTestDeps deps,
        {ActivityTab tab = ActivityTab.activity}) async {
      await pumpOwner(tester, deps, OwnerActivityPage(initialTab: tab));
    }

    testWidgets('activity: loads on open, names, labels, times',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpPage(tester, deps);

      expect(deps.owner.auditCalls, [
        {'tenantId': 'owner-1', 'token': 'owner-jwt'}
      ]);
      expect(deps.owner.dashboardCalls, isEmpty);
      expect(find.text('Arrived at Pickup'), findsOneWidget);
      expect(find.text('Karim · 10 min ago'), findsOneWidget);
      expect(find.text('Identity review completed'), findsOneWidget);
      expect(find.textContaining('You · '), findsOneWidget);
      expect(find.textContaining('emp-go'), findsOneWidget);
      // No raw machine code.
      expect(find.text('ACCOUNT_SUSPENDED'), findsNothing);
    });

    testWidgets('period filter, and "nothing in this period"', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpPage(tester, deps);

      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_activity_row_a1')), findsOneWidget);
      expect(find.byKey(const Key('own_activity_row_a2')), findsOneWidget);
      expect(find.byKey(const Key('own_activity_row_a3')), findsNothing);

      deps.owner.nextAudit = [
        audit('old', 'KYC_REVIEWED', ago: const Duration(days: 40)),
      ];
      await tester.fling(find.byKey(const Key('own_activity_list')),
          const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('own_activity_none_in_period')), findsOneWidget);
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_activity_row_old')), findsOneWidget);
    });

    testWidgets('activity loading, then empty', (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.auditGate = Completer<void>();
      await deps.data.refresh();
      await tester.pumpWidget(ownerApp(deps, const OwnerActivityPage()));
      await tester.pump();
      expect(find.byKey(const Key('own_activity_loading')), findsOneWidget);
      deps.owner.auditGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_activity_empty')), findsOneWidget);
    });

    testWidgets('activity error with retry; stale banner over old rows',
        (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextAuditError = 'down';
      await pumpPage(tester, deps);
      expect(find.byKey(const Key('own_activity_error')), findsOneWidget);

      deps.owner.nextAuditError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_activity_list')), findsOneWidget);

      deps.owner.nextAuditError = 'down again';
      await tester.fling(find.byKey(const Key('own_activity_list')),
          const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_activity_stale')), findsOneWidget);
      expect(find.text('Arrived at Pickup'), findsOneWidget);
    });

    testWidgets('money tab loads once when first shown', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpPage(tester, deps);
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(deps.owner.dashboardCalls, ['owner-jwt']);

      expect(find.text('Escrow Lock'), findsNothing);
      expect(find.byKey(const Key('own_money_row_l1')), findsOneWidget);
      expect(
          find.text(
              '\u2066#QD-B7C1D2E3\u2069 · balance after EGP 380 · 2 h ago'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Money out, EGP 120')), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Money in, EGP 120')), findsOneWidget);
      // The server's English description is not shown.
      expect(find.textContaining('escrow lock for job'), findsNothing);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(deps.owner.dashboardCalls, hasLength(1));
    });

    testWidgets('money opens directly; empty says why (cash only)',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      await pumpPage(tester, deps, tab: ActivityTab.money);
      expect(deps.owner.auditCalls, isEmpty);
      expect(find.byKey(const Key('own_money_empty')), findsOneWidget);
      expect(find.textContaining('paid in cash'), findsOneWidget);
    });

    testWidgets('money error with retry', (tester) async {
      usePhone(tester);
      final deps = deps0();
      deps.owner.nextDashboardError = 'down';
      await pumpPage(tester, deps, tab: ActivityTab.money);
      expect(find.byKey(const Key('own_money_error')), findsOneWidget);
      deps.owner.nextDashboardError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_money_list')), findsOneWidget);
    });

    testWidgets('Arabic labels render', (tester) async {
      usePhone(tester);
      final deps = deps0();
      await pumpOwner(tester, deps, const OwnerActivityPage(),
          locale: const Locale('ar'));
      expect(find.text('سجل النشاط'), findsOneWidget);
      expect(find.text('آخر 7 أيام'), findsOneWidget);
    });
  });
}
