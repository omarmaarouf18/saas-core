import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/order/order_controller.dart';
import 'package:frontend/features/customer/order/order_view.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';

// Timers run inside testWidgets' fake clock: tester.pump(d) advances it, so
// no test waits for real time.

OrderController _ctl(FakeMarketplace m,
        {String? Function()? token, Map<String, String?> names = const {}}) =>
    OrderController(
      marketplace: m,
      token: token ?? () => 'customer-jwt',
      courierName: (id) async => names[id],
      jobId: 'a1b2c3d4e5f6',
      initialJob: orderJob(),
      now: () => fixedNow,
    );

void main() {
  testWidgets('polls every 5 s while ongoing and stops when finished',
      (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob();
    final ctl = _ctl(m);

    await ctl.start();
    expect(m.statusCalls, hasLength(1));
    expect(ctl.polling, isTrue);

    await tester.pump(const Duration(seconds: 5));
    expect(m.statusCalls, hasLength(2));
    await tester.pump(const Duration(seconds: 4));
    expect(m.statusCalls, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    expect(m.statusCalls, hasLength(3));

    m.nextStatus = orderJob(status: 'completed');
    await tester.pump(const Duration(seconds: 5));
    expect(ctl.view, OrderViewKind.completed);
    expect(ctl.polling, isFalse);
    await tester.pump(const Duration(seconds: 30));
    expect(m.statusCalls, hasLength(4));
    ctl.dispose(); // before the pending-timer check
  });

  testWidgets('does not poll a job that is already finished', (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob(status: 'cancelled');
    final ctl = _ctl(m);
    await ctl.start();
    expect(ctl.polling, isFalse);
    await tester.pump(const Duration(seconds: 20));
    expect(m.statusCalls, hasLength(1));
    ctl.dispose(); // before the pending-timer check
  });

  testWidgets('stops polling on dispose', (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob();
    final ctl = _ctl(m);
    await ctl.start();
    ctl.dispose();
    await tester.pump(const Duration(seconds: 20));
    expect(m.statusCalls, hasLength(1));
  });

  testWidgets('a failed refresh keeps the last good job', (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob(status: 'active');
    final ctl = _ctl(m);
    await ctl.start();
    expect(ctl.job!.status, 'active');
    expect(ctl.error, isNull);

    m.nextStatus = null;
    await ctl.refresh();
    expect(ctl.job!.status, 'active');
    expect(ctl.error, 'Service unavailable');
    expect(ctl.polling, isTrue, reason: 'keeps trying');

    m.nextStatus = orderJob(status: 'active');
    await ctl.refresh();
    expect(ctl.error, isNull);
    ctl.dispose(); // before the pending-timer check
  });

  testWidgets('no token: no request', (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob();
    final ctl = _ctl(m, token: () => null);
    await ctl.refresh();
    expect(m.statusCalls, isEmpty);
    ctl.dispose(); // before the pending-timer check
  });

  testWidgets('resolves the courier name for the assigned or offered courier',
      (tester) async {
    final m = FakeMarketplace()
      ..nextStatus = orderJob(offeredEmployeeId: 'emp-offer');
    final ctl = _ctl(m, names: {'emp-offer': 'Karim', 'emp-1': 'Hany'});
    await ctl.start();
    await tester.pump();
    expect(ctl.courierName, 'Karim');

    ctl.setJob(orderJob(status: 'active', employeeId: 'emp-1'));
    await tester.pump();
    expect(ctl.courierName, 'Hany');
    ctl.dispose(); // before the pending-timer check
  });

  test('courierIdOf: offered courier only while dispatching', () {
    expect(
        OrderController.courierIdOf(
            orderJob(status: 'pending_dispatch', offeredEmployeeId: 'e2')),
        'e2');
    expect(
        OrderController.courierIdOf(
            orderJob(status: 'pending', offeredEmployeeId: 'e2')),
        isNull);
    expect(
        OrderController.courierIdOf(orderJob(
            status: 'active', employeeId: 'e1', offeredEmployeeId: 'e2')),
        'e1');
  });

  testWidgets('a refresh started before an action cannot overwrite it',
      (tester) async {
    final m = FakeMarketplace()..nextStatus = orderJob();
    final ctl = _ctl(m);
    m.statusGate = Completer<void>();
    final pending = ctl.refresh();
    ctl.setJob(orderJob(status: 'cancelled'));
    m.statusGate!.complete();
    await pending;
    expect(ctl.job!.status, 'cancelled');
    ctl.dispose(); // before the pending-timer check
  });
}
