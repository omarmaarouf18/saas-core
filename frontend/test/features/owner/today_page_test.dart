import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/today_page.dart';

import 'owner_harness.dart';

Future<void> _reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200,
      scrollable: find
          .descendant(
              of: find.byKey(const Key('own_today_list')),
              matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime(2026, 10, 19, 9);
  final yesterday = DateTime(2026, 10, 18, 20);

  OwnerTestDeps deps0({FakeOwnerAuth? auth}) {
    final deps = OwnerTestDeps(auth: auth);
    deps.owner.nextEmployees = [
      staff('emp-1', 'Karim'),
      staff('emp-2', 'Sara'),
      staff('emp-3', 'Mahmoud', active: false),
    ];
    deps.owner.nextJobs = [
      ownerJob(
        id: 'req-000001',
        employeeId: 'emp-1',
        createdAt: today,
        requestStatus: 'pending',
        requestReason: 'Flat tyre',
        requestedAt: ownerNow.subtract(const Duration(minutes: 5)),
      ),
      ownerJob(id: 'done-00001', status: 'completed', createdAt: today),
      ownerJob(id: 'done-00002', status: 'completed', createdAt: today),
      ownerJob(
          id: 'recon-0001',
          status: 'escrow_reconciliation_required',
          createdAt: yesterday),
      ownerJob(id: 'old-000001', status: 'completed', createdAt: yesterday),
    ];
    deps.owner.nextJobJson = {
      'done-00001': {'actual_cash_amount': 40},
      'done-00002': {'actual_cash_amount': 35.5},
      'old-000001': {'actual_cash_amount': 999},
    };
    return deps;
  }

  var showTeam = 0, showOrders = 0;
  Widget page() => Scaffold(
        body: OwnerTodayPage(
          onShowTeam: () => showTeam++,
          onShowOrders: () => showOrders++,
        ),
      );

  setUp(() => showTeam = showOrders = 0);

  testWidgets('tiles from today\'s orders; cash from recorded amounts',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    Finder tile(String k, String v) =>
        find.descendant(of: find.byKey(Key(k)), matching: find.text(v));
    expect(tile('own_tile_ongoing', '2'), findsOneWidget);
    expect(tile('own_tile_delivered', '2'), findsOneWidget);
    expect(tile('own_tile_cash', 'EGP 75.50'), findsOneWidget);
    expect(find.text('Delivered and cash count the orders placed today.'),
        findsOneWidget);
  });

  testWidgets('no cash tile when a completed COD order has no amount',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    deps.owner.nextJobJson = {
      'done-00001': {'actual_cash_amount': 40}
    };
    await pumpOwner(tester, deps, page());
    expect(find.byKey(const Key('own_tile_cash')), findsNothing);
    expect(find.byKey(const Key('own_tile_delivered')), findsOneWidget);
  });

  testWidgets('needs you: request -> order detail; review -> payment review',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    expect(find.text('Karim wants to cancel an order'), findsOneWidget);
    expect(find.text('Reason: Flat tyre · 5 min ago'), findsOneWidget);
    expect(find.text('1 order needs a payment review'), findsOneWidget);

    await tester.tap(find.text('Respond'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_cancel_request')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_recon_page')), findsOneWidget);
  });

  testWidgets('nothing needs you', (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    deps.owner.nextJobs = [ownerJob(status: 'completed')];
    await pumpOwner(tester, deps, page());
    expect(find.byKey(const Key('own_needs_nothing')), findsOneWidget);
  });

  testWidgets('team now: on a job first, frozen last; "all" -> team tab',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    final karim =
        tester.getTopLeft(find.byKey(const Key('own_team_now_emp-1')));
    final sara = tester.getTopLeft(find.byKey(const Key('own_team_now_emp-2')));
    final mahmoud =
        tester.getTopLeft(find.byKey(const Key('own_team_now_emp-3')));
    expect(karim.dy < sara.dy && sara.dy < mahmoud.dy, isTrue);
    expect(find.text('On a job'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    await tester.tap(find.text('All'));
    expect(showTeam, 1);
  });

  testWidgets('rating summary', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    await _reveal(tester, find.byKey(const Key('own_rating')));
    expect(find.text('4.6 · 23 ratings'), findsOneWidget);
    expect(deps.ratings.ratingsCalls, ['owner-jwt']);
  });

  testWidgets('rating card hidden when the fetch fails', (tester) async {
    usePhone(tester);
    final deps = deps0();
    deps.ratings.nextRatingsError = apiErr(500);
    await pumpOwner(tester, deps, page());
    await _reveal(tester, find.byKey(const Key('own_link_history')));
    expect(find.byKey(const Key('own_rating')), findsNothing);
    expect(find.byKey(const Key('own_rating_loading')), findsNothing);
  });

  for (final (status, key, text, action) in [
    (
      'pending_super_admin_approval',
      'own_kyb_pending',
      'Your documents are under review',
      'View documents'
    ),
    ('rejected', 'own_kyb_rejected', 'Blurry ID photo', 'Upload again'),
    (
      'not_submitted',
      'own_kyb_missing',
      'Verify your business',
      'Upload documents'
    ),
  ]) {
    testWidgets('KYB banner: $status -> upload screen', (tester) async {
      usePhone(tester);
      final deps = deps0(
          auth: FakeOwnerAuth(
              kycStatus: status, rejectionReason: 'Blurry ID photo'));
      await pumpOwner(tester, deps, page());
      expect(find.byKey(Key(key)), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(Key(key)), matching: find.text(action)));
      expect(deps.nav.opened, ['kyb']);
    });
  }

  testWidgets('no KYB banner when approved', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    expect(find.byKey(const Key('own_kyb_missing')), findsNothing);
    expect(find.byKey(const Key('own_kyb_pending')), findsNothing);
    expect(find.byKey(const Key('own_kyb_rejected')), findsNothing);
  });

  testWidgets('bell opens notifications; business links open old screens',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, page());
    await tester.tap(find.byKey(const Key('own_today_bell')));
    for (final k in [
      'own_link_service',
      'own_link_wallet',
      'own_link_subscription',
      'own_link_history',
    ]) {
      await _reveal(tester, find.byKey(Key(k)));
      await tester.tap(find.byKey(Key(k)));
    }
    expect(deps.nav.opened, [
      'notifications',
      'service_setup',
      'wallet',
      'subscription',
      'history',
    ]);
    await _reveal(tester, find.byKey(const Key('own_link_orders')));
    await tester.tap(find.byKey(const Key('own_link_orders')));
    expect(showOrders, 1);
  });

  testWidgets('loading, error with retry, stale banner', (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    deps.owner.jobsGate = Completer<void>();
    deps.owner.nextJobsError = 'down';
    final first = deps.data.refresh();
    await tester.pumpWidget(ownerApp(deps, page()));
    await tester.pump();
    expect(find.byKey(const Key('own_today_loading')), findsOneWidget);
    deps.owner.jobsGate!.complete();
    await first;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_today_error')), findsOneWidget);

    deps.owner.jobsGate = null;
    deps.owner.nextJobsError = null;
    deps.owner.nextJobs = [ownerJob()];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_tile_ongoing')), findsOneWidget);
    expect(deps.auth.profileCalls, 2); // KYB status refreshed too

    deps.owner.nextJobsError = 'down';
    await deps.data.refresh();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_today_stale')), findsOneWidget);
  });
}
