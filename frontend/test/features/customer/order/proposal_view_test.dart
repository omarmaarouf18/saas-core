import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

// The countdown and polling timers run on the test's fake clock; the page
// clock is a mutable fake ([clock]) moved together with tester.pump.

void main() {
  late DateTime clock;
  DateTime now() => clock;

  setUp(() => clock = fixedNow);

  Future<void> advance(WidgetTester tester, Duration d) async {
    clock = clock.add(d);
    await tester.pump(d);
  }

  final courierOffer = orderJob(
    status: 'awaiting_price_response',
    employeeId: 'emp-1',
    suggested: 40,
    proposed: 50,
    proposedBy: 'employee',
    proposalExpiresAt: fixedNow.add(const Duration(minutes: 2, seconds: 41)),
  );

  testWidgets('courier offer: comparison, difference, countdown',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, courierOffer,
        now: now, lookup: FakeCourierLookup({'emp-1': 'Karim'}));

    expect(find.byKey(const Key('ord_view_proposal')), findsOneWidget);
    expect(find.text('Karim offered a different price'), findsOneWidget);
    expect(find.text('EGP 40'), findsOneWidget);
    expect(find.text('EGP 50'), findsOneWidget);
    expect(find.text('EGP 10 more'), findsOneWidget);
    expect(find.text('02:41'), findsOneWidget);
    expect(find.text('Accept EGP 50'), findsOneWidget);
    expect(find.byKey(const Key('ord_decline')), findsOneWidget);
    expect(find.byKey(const Key('ord_offer_input')), findsNothing);

    await advance(tester, const Duration(seconds: 41));
    expect(find.text('02:00'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('a lower offer reads "less"', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(
        tester,
        deps,
        orderJob(
            status: 'awaiting_price_response',
            suggested: 40,
            proposed: 32.5,
            proposedBy: 'employee'),
        now: now);
    expect(find.text('EGP 7.50 less'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  for (final decision in ['accept', 'decline']) {
    testWidgets('$decision calls respondPrice, notice, refetch',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, courierOffer, now: now);
      final before = deps.marketplace.statusCalls.length;
      deps.marketplace.nextStatus = decision == 'accept'
          ? orderJob(status: 'active', employeeId: 'emp-1', agreed: 50)
          : orderJob(status: 'cancelled');
      await tester.tap(
          find.byKey(Key(decision == 'accept' ? 'ord_accept' : 'ord_decline')));
      await tester.pump();
      await tester.pump();

      expect(deps.marketplace.respondCalls.single['decision'], decision);
      expect(deps.marketplace.statusCalls.length, greaterThan(before));
      expect(
          find.text(decision == 'accept'
              ? 'You accepted the price.'
              : 'You declined the price.'),
          findsOneWidget);
      await unmountOrder(tester, deps);
    });
  }

  final races = {
    409:
        'The order changed: the other side already answered or its status moved on.',
    400: 'Please check your input and try again.',
    429: 'That went through already — no need to tap again.',
  };
  races.forEach((code, text) {
    testWidgets('$code on respond: notice with retry, refetch', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextPriceError =
          ApiClientException('server text', statusCode: code);
      await pumpOrder(tester, deps, courierOffer, now: now);
      final before = deps.marketplace.statusCalls.length;
      await tester.tap(find.byKey(const Key('ord_accept')));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      expect(find.text('server text'), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      expect(deps.marketplace.statusCalls.length, before + 1);
      await unmountOrder(tester, deps);
    });
  });

  testWidgets('customer offer: waiting for the courier, no buttons',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(
        tester,
        deps,
        orderJob(
          status: 'awaiting_price_response',
          suggested: 40,
          proposed: 35,
          proposedBy: 'customer',
          proposalExpiresAt: fixedNow.add(const Duration(minutes: 4)),
        ),
        now: now);
    expect(find.text('You offered EGP 35'), findsOneWidget);
    expect(find.text('Waiting for the courier to answer.'), findsOneWidget);
    expect(find.byKey(const Key('ord_accept')), findsNothing);
    expect(find.byKey(const Key('ord_decline')), findsNothing);
    expect(find.byKey(const Key('ord_send_offer')), findsNothing);
    await unmountOrder(tester, deps);
  });

  group('counter-offer (nobody proposed yet)', () {
    final open = orderJob(status: 'awaiting_price_response', suggested: 40);

    testWidgets('shows the allowed range; rejects bad input locally',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, open, now: now);
      expect(find.text('Between EGP 20 and EGP 60'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ord_offer_input')), 'abc');
      await tester.tap(find.byKey(const Key('ord_send_offer')));
      await tester.pump();
      expect(find.text('Enter a number, like 42.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ord_offer_input')), '61');
      await tester.tap(find.byKey(const Key('ord_send_offer')));
      await tester.pump();
      expect(find.text('Enter a price between EGP 20 and EGP 60.'),
          findsOneWidget);
      expect(deps.marketplace.proposeCalls, isEmpty);
      await unmountOrder(tester, deps);
    });

    testWidgets('a valid offer calls proposePrice and refetches',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, open, now: now);
      deps.marketplace.nextPriceJob = orderJob(
        status: 'awaiting_price_response',
        suggested: 40,
        proposed: 30,
        proposedBy: 'customer',
        proposalExpiresAt: fixedNow.add(const Duration(minutes: 5)),
      );
      deps.marketplace.nextStatus = deps.marketplace.nextPriceJob;
      await tester.enterText(find.byKey(const Key('ord_offer_input')), '30');
      await tester.tap(find.byKey(const Key('ord_send_offer')));
      await tester.pump();
      await tester.pump();

      expect(deps.marketplace.proposeCalls.single['price'], 30.0);
      expect(find.text('Your offer was sent.'), findsOneWidget);
      expect(find.text('You offered EGP 30'), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('409 on propose: state-changed notice and refetch',
        (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextPriceError =
          ApiClientException('job_state_changed', statusCode: 409);
      await pumpOrder(tester, deps, open, now: now);
      final before = deps.marketplace.statusCalls.length;
      await tester.enterText(find.byKey(const Key('ord_offer_input')), '45');
      await tester.tap(find.byKey(const Key('ord_send_offer')));
      await tester.pump();
      await tester.pump();
      expect(find.text(races[409]!), findsOneWidget);
      expect(deps.marketplace.statusCalls.length, before + 1);
      await unmountOrder(tester, deps);
    });
  });

  testWidgets('countdown reaching zero shows the cancelled view at once',
      (tester) async {
    final deps = CustomerTestDeps();
    final job = orderJob(
      status: 'awaiting_price_response',
      suggested: 40,
      proposed: 50,
      proposedBy: 'employee',
      proposalExpiresAt: fixedNow.add(const Duration(seconds: 3)),
    );
    // The server has not cancelled it yet: polls still return it.
    await pumpOrder(tester, deps, job, now: now);
    expect(find.byKey(const Key('ord_view_proposal')), findsOneWidget);

    await advance(tester, const Duration(seconds: 3));
    await tester.pump();
    expect(find.byKey(const Key('ord_view_cancelled')), findsOneWidget);
    expect(find.text('The price offer ran out of time'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('server-cancelled expiry reads the same', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(
        tester,
        deps,
        orderJob(
            status: 'cancelled', cancellationReason: 'price_proposal_expired'),
        now: now);
    expect(find.text('The price offer ran out of time'), findsOneWidget);
    expect(find.byKey(const Key('ord_cancel_reason')), findsNothing);
    await unmountOrder(tester, deps);
  });
}
