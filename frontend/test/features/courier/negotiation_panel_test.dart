import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/task_page.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'courier_harness.dart';

String _money(num v) => QdMoney.format(courierEn(), v);

Job _awaiting(
        {double? proposed,
        String? by,
        Duration left = const Duration(minutes: 3)}) =>
    courierJob(
      status: 'awaiting_price_response',
      proposed: proposed,
      proposedBy: by,
      proposalExpiresAt: courierNow.add(left),
    );

Future<CourierTestDeps> _pump(WidgetTester tester, Job job) async {
  usePhone(tester);
  final d = CourierTestDeps();
  d.jobs.seed([job]);
  await pumpCourier(tester, d, const CourierTaskPage());
  await tester.pumpAndSettle();
  return d;
}

Future<void> _type(WidgetTester tester, String text) async {
  final field = find.descendant(
      of: find.byKey(const Key('courier_propose_input')),
      matching: find.byType(EditableText));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<QdButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  group('propose', () {
    testWidgets('checks the input against 0.5x-1.5x the suggested price',
        (tester) async {
      final deps = await _pump(tester, _awaiting());
      expect(
          find.text('Between ${_money(21)} and ${_money(63)}'), findsOneWidget);

      await _type(tester, 'abc');
      await _tap(tester, 'courier_propose_send');
      expect(find.text('Enter a number, like 42.'), findsOneWidget);

      await _type(tester, '70');
      await _tap(tester, 'courier_propose_send');
      expect(
          find.text('Enter a price between ${_money(21)} and ${_money(63)}.'),
          findsOneWidget);
      expect(deps.jobs.calls, isEmpty);

      deps.jobs.jobsAfterAction = [_awaiting(proposed: 50, by: 'employee')];
      await _type(tester, '50');
      await _tap(tester, 'courier_propose_send');
      expect(deps.jobs.calls.single.name, 'proposePrice');
      expect(deps.jobs.calls.single.args['price'], 50.0);
      expect(
          find.text('Price sent. Waiting for the customer.'), findsOneWidget);
      expect(find.byKey(const Key('courier_negotiation_mine')), findsOneWidget);
      expect(find.text('You offered ${_money(50)}'), findsOneWidget);
    });

    testWidgets('429: the server text, no retry, no refetch', (tester) async {
      final deps = await _pump(tester, _awaiting());
      deps.jobs.nextActionError =
          courierApiError(429, 'Too many tries. Wait 5 minutes.');
      await _type(tester, '50');
      await _tap(tester, 'courier_propose_send');
      expect(find.text('Too many tries. Wait 5 minutes.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(deps.jobs.fetchCalls, 1);
    });

    testWidgets('409 race: the customer proposed first', (tester) async {
      final deps = await _pump(tester, _awaiting());
      deps.jobs.nextActionError = courierApiError(409, 'job_state_changed');
      deps.jobs.nextJobs = [_awaiting(proposed: 38, by: 'customer')];
      await _type(tester, '50');
      await _tap(tester, 'courier_propose_send');
      expect(deps.jobs.fetchCalls, 2);
      // Converged on the respond panel.
      expect(find.byKey(const Key('courier_negotiation_customer')),
          findsOneWidget);
    });

    testWidgets('400 with the job gone: the order changed', (tester) async {
      final deps = await _pump(tester, _awaiting());
      deps.jobs.nextActionError = courierApiError(400, 'invalid_job_status');
      deps.jobs.nextJobs = [courierJob(status: 'active')];
      await _type(tester, '50');
      await _tap(tester, 'courier_propose_send');
      expect(deps.jobs.fetchCalls, 2);
      expect(find.byKey(const Key('courier_action_deliver')), findsOneWidget);
    });
  });

  group('respond', () {
    testWidgets('accept asks first, then answers', (tester) async {
      final deps = await _pump(tester, _awaiting(proposed: 38, by: 'customer'));
      expect(find.text('The customer offers ${_money(38)}'), findsOneWidget);
      expect(
          find.text('The suggested price was ${_money(42)}.'), findsOneWidget);

      await _tap(tester, 'courier_price_accept');
      expect(
          find.byKey(const Key('courier_price_confirm_sheet')), findsOneWidget);
      await _tap(tester, 'courier_price_confirm_cancel');
      expect(deps.jobs.calls, isEmpty);

      deps.jobs.jobsAfterAction = [courierJob(status: 'active', agreed: 38)];
      await _tap(tester, 'courier_price_accept');
      await _tap(tester, 'courier_price_confirm');
      expect(deps.jobs.calls.single.name, 'respondPrice');
      expect(deps.jobs.calls.single.args['decision'], 'accept');
      expect(
          find.text('Price accepted. The trip has started.'), findsOneWidget);
    });

    testWidgets('decline is immediate', (tester) async {
      final deps = await _pump(tester, _awaiting(proposed: 38, by: 'customer'));
      deps.jobs.jobsAfterAction = [];
      await _tap(tester, 'courier_price_decline');
      expect(deps.jobs.calls.single.args['decision'], 'decline');
    });

    testWidgets('409: the order changed, with a refetch', (tester) async {
      final deps = await _pump(tester, _awaiting(proposed: 38, by: 'customer'));
      deps.jobs.nextActionError = courierApiError(409, 'conflict');
      await _tap(tester, 'courier_price_decline');
      expect(find.byKey(const Key('courier_price_error')), findsOneWidget);
      expect(find.textContaining('The order changed'), findsOneWidget);
      expect(deps.jobs.fetchCalls, 2);
    });

    testWidgets('429: verbatim, no retry', (tester) async {
      final deps = await _pump(tester, _awaiting(proposed: 38, by: 'customer'));
      deps.jobs.nextActionError = courierApiError(429, 'Locked for 2 minutes');
      await _tap(tester, 'courier_price_decline');
      expect(find.text('Locked for 2 minutes'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('own proposal: waiting, no answers', (tester) async {
      await _pump(tester, _awaiting(proposed: 50, by: 'employee'));
      expect(find.text("Waiting for the customer's answer."), findsOneWidget);
      expect(find.byKey(const Key('courier_price_accept')), findsNothing);
    });

    testWidgets('window over: answers disabled', (tester) async {
      await _pump(
          tester, _awaiting(proposed: 38, by: 'customer', left: Duration.zero));
      expect(find.byKey(const Key('courier_price_expired')), findsOneWidget);
      expect(_enabled(tester, 'courier_price_accept'), isFalse);
      expect(_enabled(tester, 'courier_price_decline'), isFalse);
    });
  });
}
