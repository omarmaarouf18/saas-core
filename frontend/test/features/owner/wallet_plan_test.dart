import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/owner/activity_log_page.dart';
import 'package:frontend/features/owner/plan_page.dart';
import 'package:frontend/features/owner/plan_rules.dart';
import 'package:frontend/features/owner/wallet_page.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'owner_harness.dart';

// FE-OWNER-2b item 6: read-only wallet and plan.

PayoutRequest payout(String id, String status,
        {double amount = 200,
        String method = 'instapay',
        String? reason,
        String? account}) =>
    PayoutRequest(
      id: id,
      tenantId: 'owner-1',
      amount: amount,
      status: status,
      payoutMethod: method,
      rejectionReason: reason,
      accountDetails: account,
      createdAt: ownerNow.subtract(const Duration(days: 2)),
      updatedAt: ownerNow.subtract(const Duration(days: 2)),
    );

Map<String, dynamic> entry(String id, String type, double amount,
        {double before = 0, double after = 0, String? job}) =>
    {
      'id': id,
      'type': type,
      'amount': amount,
      'balance_before': before,
      'balance_after': after,
      if (job != null) 'job_id': job,
      'timestamp':
          ownerNow.subtract(const Duration(hours: 3)).toUtc().toIso8601String(),
    };

void _wallet(OwnerTestDeps deps, {String tier = 'paid'}) {
  deps.owner.nextWallet =
      (total: 1250, escrow: 150, withdrawable: 1100, tier: tier);
  deps.owner.nextLedger = [
    for (var i = 0; i < 7; i++)
      entry('l$i', 'escrow_release', 100.0 + i,
          before: 1000, after: 1100.0 + i, job: 'a1b2c3d4e5f6'),
  ];
  deps.owner.nextPayouts = [
    payout('p1', 'paid', account: 'IBAN EG12 3456'),
    payout('p2', 'rejected', amount: 90, reason: 'Account name mismatch'),
  ];
}

Future<void> _pump(WidgetTester tester, OwnerTestDeps deps, Widget page,
    {Locale locale = const Locale('en')}) async {
  usePhone(tester);
  await pumpOwner(tester, deps, page, refresh: false, locale: locale);
}

/// Scrolls the plan page until [key] is built, then centres it.
Future<void> _show(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  final list = find.descendant(
      of: find.byKey(const Key('own_plan_list')),
      matching: find.byType(Scrollable));
  tester.state<ScrollableState>(list.first).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(f, 200, scrollable: list.first);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  group('plan rules', () {
    final l10n = AppLocalizationsEn();
    test('tiers', () {
      expect(planTierOf('paid'), PlanTier.paid);
      expect(planTierOf(null), PlanTier.free);
      expect(planTierOf('pending_payment'), PlanTier.pending);
      expect(planTierOf('canceled'), PlanTier.cancelled);
      expect(planTierOf('gold'), PlanTier.unknown);
      expect(planLabel(l10n, 'paid'), 'Paid');
      expect(planLabel(l10n, 'pending_payment'), 'Under review');
    });

    test('access mirrors IsClosed (ADR-0024)', () {
      final now = DateTime(2026, 10, 19);
      expect(planAccessOf('paid', null, now), PlanAccess.open);
      expect(planAccessOf('paid', DateTime(2026, 11, 1), now),
          PlanAccess.openUntil);
      expect(
          planAccessOf('paid', DateTime(2026, 10, 1), now), PlanAccess.expired);
      for (final t in ['free', 'pending_payment', 'cancelled', 'x']) {
        expect(planAccessOf(t, null, now), PlanAccess.closed, reason: t);
      }
    });

    test('payout chips', () {
      expect(payoutStatusChip(l10n, 'paid').$1, 'Paid');
      expect(payoutStatusChip(l10n, 'REJECTED').$1, 'Rejected');
      expect(payoutStatusChip(l10n, 'weird').$1, 'Unknown status');
    });
  });

  group('wallet', () {
    testWidgets('balances, withdrawals, latest five movements', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      await _pump(tester, deps, const OwnerWalletPage());
      expect(deps.owner.dashboardCalls, ['owner-jwt']);
      expect(deps.owner.payoutCalls, 1);
      expect(find.text('EGP 1,100'), findsOneWidget);
      expect(find.text('EGP 1,250'), findsOneWidget);
      expect(find.text('EGP 150'), findsOneWidget);
      expect(find.byKey(const Key('own_payout_p1')), findsOneWidget);
      expect(find.text('IBAN EG12 3456'), findsOneWidget);
      expect(find.text('Reason: Account name mismatch'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.byKey(const Key('own_money_row_l4')), 200);
      expect(find.byKey(const Key('own_money_row_l5')), findsNothing);
      // No "$" anywhere.
      expect(find.textContaining(r'$'), findsNothing);
    });

    testWidgets('add money and withdraw only say "coming soon"',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      await _pump(tester, deps, const OwnerWalletPage());
      await tester.tap(find.byKey(const Key('own_wallet_add')));
      await tester.pump();
      expect(find.byKey(const Key('own_wallet_soon')), findsOneWidget);
      await tester.tap(find.byKey(const Key('own_wallet_withdraw')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_wallet_soon')), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(deps.owner.moneyCalls, isEmpty);
    });

    testWidgets('"see all" opens the Money tab of the activity log',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      await _pump(tester, deps, const OwnerWalletPage());
      await tester.scrollUntilVisible(find.text('See all'), 200);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      final page =
          tester.widget<OwnerActivityPage>(find.byType(OwnerActivityPage));
      expect(page.initialTab, ActivityTab.money);
    });

    testWidgets('loader before the first load, then the error with retry',
        (tester) async {
      final deps = OwnerTestDeps();
      deps.owner.dashboardGate = Completer<void>();
      deps.owner.nextDashboardError = 'offline';
      usePhone(tester);
      await tester.pumpWidget(ownerApp(deps, const OwnerWalletPage()));
      await tester.pump();
      expect(find.byKey(const Key('own_wallet_loading')), findsOneWidget);
      expect(find.text('EGP 0'), findsNothing);
      deps.owner.dashboardGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_wallet_error')), findsOneWidget);
      deps.owner.dashboardGate = null;
      deps.owner.nextDashboardError = null;
      _wallet(deps);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('EGP 1,100'), findsOneWidget);
    });

    testWidgets('failed refresh over loaded data: stale banner',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      await _pump(tester, deps, const OwnerWalletPage());
      deps.owner.nextDashboardError = 'offline';
      await tester.fling(
          find.byKey(const Key('own_wallet_list')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_wallet_stale')), findsOneWidget);
      expect(find.text('EGP 1,100'), findsOneWidget);
      expect(deps.owner.dashboardCalls, hasLength(2));
      expect(deps.owner.payoutCalls, 2);
    });

    testWidgets('withdrawals: empty and error states', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      deps.owner.nextPayouts = [];
      deps.owner.nextLedger = [];
      await _pump(tester, deps, const OwnerWalletPage());
      expect(find.byKey(const Key('own_wallet_payouts_empty')), findsOneWidget);
      expect(find.byKey(const Key('own_wallet_recent_empty')), findsOneWidget);
      expect(find.text('See all'), findsNothing);

      deps.owner.nextPayoutsError = 'down';
      await tester.fling(
          find.byKey(const Key('own_wallet_list')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_wallet_payouts_error')), findsOneWidget);
      expect(find.byKey(const Key('own_wallet_payouts_empty')), findsNothing);
    });

    testWidgets('Arabic builds without overflow', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      await _pump(tester, deps, const OwnerWalletPage(),
          locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
      expect(find.text('المحفظة'), findsOneWidget);
    });
  });

  group('plan', () {
    testWidgets('paid with an expiry: open until the date, switch to free',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      deps.owner.nextExpiresAt = DateTime(2026, 11, 30);
      await _pump(tester, deps, const OwnerPlanPage());
      expect(deps.owner.dashboardCalls, ['owner-jwt']);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.byKey(const Key('own_plan_openUntil')), findsOneWidget);
      expect(find.textContaining('Active until Nov 30, 2026'), findsOneWidget);
      // Open paid plan: nothing to request.
      expect(find.byKey(const Key('own_plan_upgrade')), findsNothing);
      await _show(tester, 'own_plan_downgrade');
      await tester.tap(find.byKey(const Key('own_plan_downgrade')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_plan_downgrade_sheet')), findsOneWidget);
      expect(
          find.textContaining("won't be able to find or book"), findsOneWidget);
      // Not now: nothing sent.
      await tester.tap(find.byKey(const Key('own_confirm_no')));
      await tester.pumpAndSettle();
      expect(deps.owner.subscriptionCalls, isEmpty);
      await tester.tap(find.byKey(const Key('own_plan_downgrade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('own_confirm_yes')));
      await tester.pumpAndSettle();
      expect(deps.owner.subscriptionCalls, ['owner-jwt:free']);
      expect(find.text("You're on the free plan now."), findsOneWidget);
      expect(deps.owner.dashboardCalls, hasLength(2));
      expect(find.byKey(const Key('own_plan_closed')), findsOneWidget);
      expect(deps.owner.moneyCalls, isEmpty);
    });

    testWidgets('free: request upgrade, then under review and disabled',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps, tier: 'free');
      await _pump(tester, deps, const OwnerPlanPage());
      expect(find.text('Free'), findsOneWidget);
      expect(find.byKey(const Key('own_plan_closed')), findsOneWidget);
      expect(find.byKey(const Key('own_plan_downgrade')), findsNothing);
      await _show(tester, 'own_plan_upgrade');
      await tester.tap(find.byKey(const Key('own_plan_upgrade')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_plan_upgrade_sheet')), findsOneWidget);
      expect(find.text('Request the paid plan?'), findsOneWidget);
      expect(find.textContaining('pay'), findsNothing);
      await tester.tap(find.byKey(const Key('own_confirm_yes')));
      await tester.pumpAndSettle();
      expect(deps.owner.subscriptionCalls, ['owner-jwt:paid']);
      expect(find.text('Request sent. Your plan is under review.'),
          findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.byKey(const Key('own_plan_pending')), findsOneWidget);
      await _show(tester, 'own_plan_upgrade');
      final up =
          tester.widget<QdButton>(find.byKey(const Key('own_plan_upgrade')));
      expect(up.onPressed, isNull);
      // Switching to free (cancelling the request) stays available.
      await _show(tester, 'own_plan_downgrade');
      await tester.tap(find.byKey(const Key('own_plan_downgrade')));
      await tester.pumpAndSettle();
      expect(find.text('This cancels your upgrade request.'), findsOneWidget);
    });

    testWidgets('a failed request: notice with retry; 429 verbatim',
        (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps, tier: 'free');
      deps.owner.nextSubscriptionError = ApiClientException(
          'too many requests; retry in 42 seconds',
          statusCode: 429);
      await _pump(tester, deps, const OwnerPlanPage());
      await _show(tester, 'own_plan_upgrade');
      await tester.tap(find.byKey(const Key('own_plan_upgrade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('own_confirm_yes')));
      await tester.pumpAndSettle();
      expect(
          find.text('too many requests; retry in 42 seconds'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.owner.subscriptionCalls, hasLength(2));
      expect(find.text('Under review'), findsOneWidget);
    });

    testWidgets('one change at a time', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps, tier: 'free');
      deps.owner.subscriptionGate = Completer<void>();
      await _pump(tester, deps, const OwnerPlanPage());
      await _show(tester, 'own_plan_upgrade');
      await tester.tap(find.byKey(const Key('own_plan_upgrade')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('own_confirm_yes')));
      await tester.pump();
      await tester.pump();
      final up =
          tester.widget<QdButton>(find.byKey(const Key('own_plan_upgrade')));
      expect(up.onPressed, isNull);
      deps.owner.subscriptionGate!.complete();
      await tester.pumpAndSettle();
      expect(deps.owner.subscriptionCalls, hasLength(1));
    });

    testWidgets('support link', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps, tier: 'free');
      await _pump(tester, deps, const OwnerPlanPage());
      await _show(tester, 'own_plan_support');
      await tester.tap(find.byKey(const Key('own_plan_support')));
      expect(deps.nav.opened, ['support']);
    });

    testWidgets('expired paid plan', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      deps.owner.nextExpiresAt = DateTime(2026, 10, 1);
      await _pump(tester, deps, const OwnerPlanPage());
      expect(find.byKey(const Key('own_plan_expired')), findsOneWidget);
      expect(find.textContaining('Ended on Oct 1, 2026'), findsOneWidget);
    });

    testWidgets('pending payment shows the activation note', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps, tier: 'pending_payment');
      await _pump(tester, deps, const OwnerPlanPage());
      expect(find.text('Under review'), findsOneWidget);
      expect(find.byKey(const Key('own_plan_pending')), findsOneWidget);
      await _show(tester, 'own_plan_upgrade');
      expect(
          tester
              .widget<QdButton>(find.byKey(const Key('own_plan_upgrade')))
              .onPressed,
          isNull);
    });

    testWidgets('loader, never the default free tier, then error and retry',
        (tester) async {
      final deps = OwnerTestDeps();
      deps.owner.dashboardGate = Completer<void>();
      deps.owner.nextDashboardError = 'offline';
      usePhone(tester);
      await tester.pumpWidget(ownerApp(deps, const OwnerPlanPage()));
      await tester.pump();
      expect(find.byKey(const Key('own_plan_loading')), findsOneWidget);
      expect(find.text('Free'), findsNothing);
      deps.owner.dashboardGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_plan_error')), findsOneWidget);
      deps.owner.dashboardGate = null;
      deps.owner.nextDashboardError = null;
      _wallet(deps);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_plan_open')), findsOneWidget);
    });

    testWidgets('Arabic builds without overflow', (tester) async {
      final deps = OwnerTestDeps();
      _wallet(deps);
      deps.owner.nextExpiresAt = DateTime(2026, 11, 30);
      await _pump(tester, deps, const OwnerPlanPage(),
          locale: const Locale('ar'));
      expect(tester.takeException(), isNull);
      expect(find.text('مدفوعة'), findsOneWidget);
    });
  });
}
