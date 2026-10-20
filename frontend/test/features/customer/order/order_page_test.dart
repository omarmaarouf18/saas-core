import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/customer_nav.dart';
import 'package:frontend/features/customer/order/order_deps.dart';
import 'package:frontend/features/customer/order/order_detail_page.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

void main() {
  group('page', () {
    testWidgets('without a first copy: loader, then the view', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace
        ..nextStatus = orderJob(status: 'pending')
        ..statusGate = Completer<void>();
      usePhone(tester);
      await tester.pumpWidget(CourierLookupScope(
        lookup: FakeCourierLookup(),
        child: customerApp(
            deps, OrderDetailPage(jobId: 'a1b2c3d4e5f6', now: () => fixedNow)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ord_loading')), findsOneWidget);

      deps.marketplace.statusGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);
      expect(deps.marketplace.statusCalls, ['a1b2c3d4e5f6']);
      await unmountOrder(tester, deps);
    });

    testWidgets('without a first copy: load error with retry', (tester) async {
      final deps = CustomerTestDeps();
      usePhone(tester);
      await tester.pumpWidget(CourierLookupScope(
        lookup: FakeCourierLookup(),
        child: customerApp(
            deps, OrderDetailPage(jobId: 'a1b2c3d4e5f6', now: () => fixedNow)),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ord_load_error')), findsOneWidget);
      expect(find.text("We couldn't load your order"), findsOneWidget);

      deps.marketplace.nextStatus = orderJob(status: 'active');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ord_view_active')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('a status change from the poll switches the view',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending_dispatch'));
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);

      deps.marketplace.nextStatus =
          orderJob(status: 'active', employeeId: 'e1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const Key('ord_view_active')), findsOneWidget);

      deps.marketplace.nextStatus =
          orderJob(status: 'completed', employeeId: 'e1');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const Key('ord_view_completed')), findsOneWidget);
      final calls = deps.marketplace.statusCalls.length;
      await tester.pump(const Duration(seconds: 20));
      expect(deps.marketplace.statusCalls.length, calls,
          reason: 'stops polling once finished');
      await unmountOrder(tester, deps);
    });

    testWidgets('closing the page stops polling', (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending'));
      await unmountOrder(tester, deps);
      final calls = deps.marketplace.statusCalls.length;
      await tester.pump(const Duration(seconds: 20));
      expect(deps.marketplace.statusCalls.length, calls);
    });

    testWidgets('a failed poll keeps the last good data under a banner',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending'));
      deps.marketplace.nextStatus = null;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.byKey(const Key('ord_stale_banner')), findsOneWidget);
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);
      expect(find.text('Beside the kiosk'), findsOneWidget);

      deps.marketplace.nextStatus = orderJob(status: 'pending');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ord_stale_banner')), findsNothing);
      await unmountOrder(tester, deps);
    });

    testWidgets('pull to refresh refetches', (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending'));
      final calls = deps.marketplace.statusCalls.length;
      await tester.fling(
          find.byKey(const Key('ord_list')), const Offset(0, 400), 1000);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(deps.marketplace.statusCalls.length, greaterThan(calls));
      await unmountOrder(tester, deps);
    });
  });

  group('closed views', () {
    testWidgets('cancelled with a reason; cancellation chip kept',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(
          tester,
          deps,
          orderJob(
              status: 'cancelled',
              cancellationReason: 'Courier could not reach you'));
      expect(find.text('Order cancelled'), findsOneWidget);
      expect(find.text('Reason: Courier could not reach you'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
      expect(find.byKey(const Key('ord_cancel')), findsNothing);
      await unmountOrder(tester, deps);
    });

    testWidgets('cancelled without a reason', (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'canceled'));
      expect(find.text('Order cancelled'), findsOneWidget);
      expect(find.byKey(const Key('ord_cancel_reason')), findsNothing);
      await unmountOrder(tester, deps);
    });

    testWidgets('under review: amount on hold, keeps polling', (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(
          tester,
          deps,
          orderJob(
              status: 'escrow_reconciliation_required',
              employeeId: 'e1',
              lockedEscrow: 42.5));
      expect(find.text('Your order is under review'), findsOneWidget);
      expect(find.text('Amount on hold'), findsOneWidget);
      expect(find.text('EGP 42.50'), findsOneWidget);
      final calls = deps.marketplace.statusCalls.length;
      await tester.pump(const Duration(seconds: 5));
      expect(deps.marketplace.statusCalls.length, calls + 1);
      await unmountOrder(tester, deps);
    });

    testWidgets('unknown status: summary, no actions', (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'picked_up'));
      expect(find.byKey(const Key('ord_view_unknown')), findsOneWidget);
      expect(find.text("We can't show this order's status"), findsOneWidget);
      expect(find.text('Unknown status'), findsOneWidget);
      for (final k in [
        'ord_cancel',
        'ord_retry_booking',
        'ord_accept',
        'ord_decline',
        'ord_send_offer',
        'ord_rate',
        'ord_complaint',
      ]) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      await unmountOrder(tester, deps);
    });

    testWidgets('employee cancellation request shows as a chip',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(
          tester,
          deps,
          orderJob(
              status: 'active',
              employeeId: 'e1',
              cancellationRequestStatus: 'pending'));
      expect(find.text('Cancellation requested'), findsOneWidget);
      await unmountOrder(tester, deps);
    });
  });

  group('call sites', () {
    testWidgets('CustomerNav.openOrder pushes the order page', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextStatus = orderJob(status: 'pending');
      usePhone(tester);
      await tester.pumpWidget(CourierLookupScope(
        lookup: FakeCourierLookup(),
        child: customerApp(
          deps,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => const CustomerNav()
                  .openOrder(context, orderJob(status: 'pending')),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final page = tester.widget<OrderDetailPage>(find.byType(OrderDetailPage));
      expect(page.jobId, 'a1b2c3d4e5f6');
      expect(page.initialJob, isNotNull);
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('after booking, back returns to the first page',
        (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextStatus = orderJob(status: 'pending');
      usePhone(tester);
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(CourierLookupScope(
        lookup: FakeCourierLookup(),
        child: customerApp(deps, const Text('shell')),
      ));
      final ctx = tester.element(find.text('shell'));
      Navigator.of(ctx).push(MaterialPageRoute<void>(
          builder: (_) => Builder(
              key: navKey,
              builder: (c) => TextButton(
                    onPressed: () => const CustomerNav().openOrder(
                        c, orderJob(status: 'pending'),
                        replaceStack: true),
                    child: const Text('book'),
                  ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('book'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(OrderDetailPage), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('shell'), findsOneWidget);
      expect(find.text('book'), findsNothing);
      await unmountOrder(tester, deps);
    });
  });

  for (final locale in bothLocales) {
    for (final status in [
      'pending_dispatch',
      'unavailable',
      'awaiting_price_response',
      'active',
      'escrow_reconciliation_required',
      'completed',
      'cancelled',
      'weird',
    ]) {
      testWidgets('$status renders without overflow [${locale.languageCode}]',
          (tester) async {
        final deps = CustomerTestDeps();
        await pumpOrder(
          tester,
          deps,
          orderJob(
            status: status,
            employeeId: status == 'active' ? 'e1' : null,
            offeredEmployeeId: 'e2',
            pickupNote: 'A very long landmark note ' * 4,
            dropNote: 'Another very long landmark note ' * 4,
            proposed: status == 'awaiting_price_response' ? 61.75 : null,
            proposedBy: 'employee',
            proposalExpiresAt: fixedNow.add(const Duration(minutes: 3)),
            cancellationReason: 'A long reason ' * 6,
            cancellationRequestStatus: 'pending',
          ),
          locale: locale,
          lookup: FakeCourierLookup({'e1': 'Abdelrahman Mohamed', 'e2': 'Ali'}),
        );
        expect(tester.takeException(), isNull);
        await unmountOrder(tester, deps);
      });
    }
  }
}
