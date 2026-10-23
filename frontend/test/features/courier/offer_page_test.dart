import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/task_page.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'courier_harness.dart';

Job _offer({Duration left = const Duration(seconds: 40)}) => courierJob(
      status: 'pending_dispatch',
      offerExpiresAt: courierNow.add(left),
      pickupAddress: '15 Qasr El Nil St',
      pickupNote: 'Third floor',
      dropAddress: null,
      dropNote: 'Zamalek, 26th of July St',
      package: const JobPackageDetails(size: 'small', notes: 'Documents'),
    );

Future<CourierTestDeps> _pump(WidgetTester tester, Job offer,
    {CourierTestDeps? deps}) async {
  usePhone(tester);
  final d = deps ?? CourierTestDeps();
  d.jobs.seed([offer]);
  await pumpCourier(tester, d, const CourierTaskPage());
  return d;
}

Finder _button(String key) => find.byKey(Key(key));

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<QdButton>(_button(key)).onPressed != null;

void main() {
  testWidgets('shows route, package, price and the countdown', (tester) async {
    final deps = CourierTestDeps();
    deps.location.lastKnownPosition = position(30.0500, 31.2400);
    await _pump(tester, _offer(), deps: deps);

    expect(find.byKey(const Key('courier_offer')), findsOneWidget);
    expect(find.byKey(const Key('courier_offer_countdown')), findsOneWidget);
    expect(find.text('00:40'), findsOneWidget);
    // Address text first, the note under it; a note alone is the title.
    expect(find.text('15 Qasr El Nil St'), findsOneWidget);
    expect(find.text('Third floor'), findsOneWidget);
    expect(find.text('Zamalek, 26th of July St'), findsOneWidget);
    expect(find.textContaining('from you'), findsOneWidget);
    expect(find.textContaining('Drop-off · trip 2.3 km'), findsOneWidget);
    expect(find.text('Package: Small · Documents'), findsOneWidget);
    expect(find.text("You'll collect cash"), findsOneWidget);
    expect(find.byKey(const Key('courier_offer_price')), findsOneWidget);
    expect(_enabled(tester, 'courier_offer_accept'), isTrue);
    expect(_enabled(tester, 'courier_offer_decline'), isTrue);
  });

  testWidgets('no position, no note, no destination: honest fallbacks',
      (tester) async {
    await _pump(
        tester,
        courierJob(
          status: 'pending_dispatch',
          offerExpiresAt: courierNow.add(const Duration(seconds: 30)),
          pickupNote: null,
          withDestination: false,
          price: null,
        ));
    expect(find.text('Pinned location'), findsOneWidget);
    expect(find.text('Drop-off not set yet'), findsOneWidget);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Not set yet'), findsOneWidget);
    expect(find.byKey(const Key('courier_package')), findsNothing);
  });

  testWidgets('expired offer: answers and chat are disabled', (tester) async {
    await _pump(tester, _offer(left: const Duration(seconds: -1)));
    await tester.pump();
    expect(find.byKey(const Key('courier_offer_expired')), findsOneWidget);
    expect(_enabled(tester, 'courier_offer_accept'), isFalse);
    expect(_enabled(tester, 'courier_offer_decline'), isFalse);
    expect(_enabled(tester, 'courier_offer_chat'), isFalse);
  });

  testWidgets('the countdown ending disables the answers and refetches',
      (tester) async {
    final deps = await _pump(tester, _offer(left: const Duration(seconds: 2)));
    expect(deps.jobs.fetchCalls, 1);
    expect(_enabled(tester, 'courier_offer_accept'), isTrue);

    deps.clock = courierNow.add(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_enabled(tester, 'courier_offer_accept'), isFalse);
    expect(deps.jobs.fetchCalls, 2);
  });

  testWidgets('accept: one call, a notice and a refetch', (tester) async {
    final deps = await _pump(tester, _offer());
    deps.jobs.actionGate = Completer<void>();
    await tester.tap(_button('courier_offer_accept'));
    await tester.pump();
    // A second tap while in flight is ignored.
    await tester.tap(_button('courier_offer_accept'), warnIfMissed: false);
    deps.jobs.jobsAfterAction = [courierJob(status: 'active')];
    deps.jobs.actionGate!.complete();
    await tester.pumpAndSettle();
    expect(deps.jobs.calls.map((c) => c.name), ['accept']);
    expect(find.text('Task accepted'), findsOneWidget);
    expect(deps.jobs.fetchCalls, 2);
  });

  testWidgets('accept race: someone else took it (409)', (tester) async {
    final deps = await _pump(tester, _offer());
    deps.jobs.nextActionError = courierApiError(409, 'job is not available');
    deps.jobs.nextJobs = [];
    await tester.tap(_button('courier_offer_accept'));
    await tester.pumpAndSettle();
    expect(find.text('This offer is no longer available.'), findsOneWidget);
    expect(deps.jobs.fetchCalls, 2);
    // The refetch dropped the offer: back to waiting.
    expect(find.byKey(const Key('courier_task_idle')), findsOneWidget);
  });

  testWidgets('accept fails for another reason: friendly message',
      (tester) async {
    final deps = await _pump(tester, _offer());
    deps.jobs.nextActionError = courierApiError(503, 'Service unavailable');
    await tester.tap(_button('courier_offer_accept'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('courier_offer_error')), findsOneWidget);
    expect(find.text('This offer is no longer available.'), findsNothing);
    expect(deps.jobs.fetchCalls, 2);
  });

  testWidgets('decline: one call, a notice and a refetch', (tester) async {
    final deps = await _pump(tester, _offer());
    deps.jobs.jobsAfterAction = [];
    await tester.tap(_button('courier_offer_decline'));
    await tester.pumpAndSettle();
    expect(deps.jobs.calls.single.name, 'decline');
    expect(find.text('Offer declined'), findsOneWidget);
    expect(deps.jobs.fetchCalls, 2);
  });

  testWidgets('ask the customer opens the job chat', (tester) async {
    final deps = await _pump(tester, _offer());
    await tester.tap(_button('courier_offer_chat'));
    expect(deps.nav.opened, ['chat:a1b2c3d4e5f6']);
  });
}
