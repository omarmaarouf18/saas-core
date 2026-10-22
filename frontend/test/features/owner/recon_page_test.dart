import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/recon_page.dart';

import 'owner_harness.dart';

void main() {
  OwnerTestDeps deps0() {
    final deps = OwnerTestDeps();
    deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
    deps.recon.nextQueue = [
      reconJob(),
      reconJob(id: 'x9y8z7w6v5u4', reason: 'implausible_speed', held: 80),
    ];
    return deps;
  }

  testWidgets('cards: reason chip, held amount, courier, customer, note',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const OwnerReconPage());
    expect(deps.recon.queueCalls, 1);
    expect(find.text('Distance shorter than expected'), findsOneWidget);
    expect(find.text("Speed didn't add up"), findsOneWidget);
    expect(find.text('EGP 120'), findsOneWidget);
    expect(find.text('Karim'), findsNWidgets(2));
    expect(find.text('tracked 1.2 km of 6.0 km booked'), findsNWidgets(2));
    await tester.dragUntilVisible(find.byKey(const Key('own_recon_cod_note')),
        find.byKey(const Key('own_recon_list')), const Offset(0, -300));
    expect(find.byKey(const Key('own_recon_cod_note')), findsOneWidget);
  });

  testWidgets('release after confirm; the card leaves the list',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const OwnerReconPage());
    await tester.tap(find.byKey(const Key('own_recon_pay_r1s2t3u4v5w6')));
    await tester.pumpAndSettle();
    expect(find.text('Pay the courier?'), findsOneWidget);
    expect(find.textContaining('EGP 120 for order'), findsOneWidget);
    expect(find.textContaining('goes to Karim'), findsOneWidget);
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pumpAndSettle();
    expect(deps.recon.resolveCalls, [
      {'jobId': 'r1s2t3u4v5w6', 'decision': 'release_to_employee'}
    ]);
    expect(find.text('Paid to the courier.'), findsOneWidget);
    expect(find.byKey(const Key('own_recon_r1s2t3u4v5w6')), findsNothing);
  });

  testWidgets('refund: "not now" sends nothing', (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const OwnerReconPage());
    await tester.tap(find.byKey(const Key('own_recon_refund_r1s2t3u4v5w6')));
    await tester.pumpAndSettle();
    expect(find.text('Refund the customer?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('own_confirm_no')));
    await tester.pumpAndSettle();
    expect(deps.recon.resolveCalls, isEmpty);
  });

  testWidgets('one resolution at a time: every action locked while in flight',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const OwnerReconPage());
    deps.recon.resolveGate = Completer<void>();
    await tester.tap(find.byKey(const Key('own_recon_refund_r1s2t3u4v5w6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('own_recon_pay_x9y8z7w6v5u4')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const Key('own_confirm_sheet')), findsNothing);
    expect(find.byKey(const Key('own_recon_confirm_release_to_employee')),
        findsNothing);
    expect(deps.recon.resolveCalls.length, 1);

    deps.recon.resolveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Refunded to the customer.'), findsOneWidget);
  });

  testWidgets('a failed resolution: notice with retry, card stays',
      (tester) async {
    usePhone(tester);
    final deps = deps0();
    await pumpOwner(tester, deps, const OwnerReconPage());
    deps.recon.nextResolveError = 'Escrow service unavailable';
    await tester.tap(find.byKey(const Key('own_recon_pay_r1s2t3u4v5w6')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own_confirm_yes')));
    await tester.pumpAndSettle();
    expect(find.text('Escrow service unavailable'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    expect(find.byKey(const Key('own_recon_r1s2t3u4v5w6')), findsOneWidget);

    deps.recon.nextResolveError = null;
    await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Pay the courier?'), findsOneWidget);
  });

  testWidgets('loading, error with retry, empty with the COD note',
      (tester) async {
    usePhone(tester);
    final deps = OwnerTestDeps();
    deps.recon.queueGate = Completer<void>();
    deps.recon.nextQueueError = 'down';
    await tester.pumpWidget(ownerApp(deps, const OwnerReconPage()));
    await tester.pump();
    expect(find.byKey(const Key('own_recon_loading')), findsOneWidget);
    deps.recon.queueGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_recon_error')), findsOneWidget);

    deps.recon.queueGate = null;
    deps.recon.nextQueueError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('own_recon_empty')), findsOneWidget);
    expect(find.text('With cash payment only'), findsOneWidget);
  });
}
