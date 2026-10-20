import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/chat/chat_page.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

void main() {
  group('searching', () {
    testWidgets('pending: rings, route, price, cancel; no courier card',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending'));

      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);
      expect(find.text('Looking for a courier'), findsOneWidget);
      expect(find.text('Beside the kiosk'), findsOneWidget);
      expect(find.text('Zamalek, 26th of July St'), findsOneWidget);
      expect(find.text('Cash · estimated'), findsOneWidget);
      expect(find.text('EGP 42'), findsOneWidget);
      expect(find.byKey(const Key('ord_offered_courier')), findsNothing);
      expect(find.byKey(const Key('ord_cancel')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('company name when its service is loaded', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.services = [service(name: 'Nile Express')];
      await pumpOrder(tester, deps, orderJob(status: 'pending'));
      expect(
          find.text(
              'We offer your order to Nile Express couriers one by one until one accepts.'),
          findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('offered courier: name, early chat opens job chat',
        (tester) async {
      final deps = CustomerTestDeps();
      final lookup = FakeCourierLookup({'emp-9': 'Karim'});
      await pumpOrder(tester, deps,
          orderJob(status: 'pending_dispatch', offeredEmployeeId: 'emp-9'),
          lookup: lookup);

      expect(find.text('Karim is looking at your order'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ord_chat')));
      await tester.pumpAndSettle();
      final chat =
          tester.widget<CustomerChatPage>(find.byType(CustomerChatPage));
      expect(chat.channel, 'job:a1b2c3d4e5f6');
      await unmountOrder(tester, deps);
    });

    testWidgets('offered courier whose name cannot be resolved',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps,
          orderJob(status: 'pending_dispatch', offeredEmployeeId: 'emp-9'));
      expect(find.text('A courier is looking at your order'), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('cancel: reason required, cancelJob, notice, refetch',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, orderJob(status: 'pending_dispatch'));

      await tester.tap(find.byKey(const Key('ord_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ord_cancel_sheet')), findsOneWidget);
      // Disabled until a reason is typed.
      await tester.tap(find.byKey(const Key('ord_cancel_confirm')));
      await tester.pump();
      expect(deps.marketplace.cancelCalls, isEmpty);

      final fetchesBefore = deps.marketplace.statusCalls.length;
      deps.marketplace.nextStatus =
          orderJob(status: 'cancelled', cancellationReason: 'Changed my mind');
      await tester.enterText(find.byKey(const Key('ord_cancel_reason_input')),
          ' Changed my mind ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ord_cancel_confirm')));
      await tester.pumpAndSettle();

      expect(deps.marketplace.cancelCalls.single['reason'], 'Changed my mind');
      expect(deps.marketplace.statusCalls.length, greaterThan(fetchesBefore));
      expect(find.text('Your order was cancelled.'), findsOneWidget);
      expect(find.byKey(const Key('ord_view_cancelled')), findsOneWidget);
      expect(find.text('Reason: Changed my mind'), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('cancel failure keeps the sheet open with the error',
        (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextCancelError = apiError();
      await pumpOrder(tester, deps, orderJob(status: 'pending'));
      await tester.tap(find.byKey(const Key('ord_cancel')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('ord_cancel_reason_input')), 'Late');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ord_cancel_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ord_cancel_sheet')), findsOneWidget);
      expect(find.byKey(const Key('ord_cancel_error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ord_cancel_keep')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ord_cancel_sheet')), findsNothing);
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);
      await unmountOrder(tester, deps);
    });

    testWidgets('non-COD job cancelled before dispatch mentions the refund',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(
          tester, deps, orderJob(status: 'pending', paymentMethod: 'wallet'));
      deps.marketplace.nextStatus = orderJob(status: 'cancelled');
      await tester.tap(find.byKey(const Key('ord_cancel')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('ord_cancel_reason_input')), 'Late');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ord_cancel_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Your order was cancelled and the amount was refunded.'),
          findsOneWidget);
      await unmountOrder(tester, deps);
    });
  });

  group('unavailable', () {
    testWidgets('retry books the same trip and follows the new job',
        (tester) async {
      final deps = CustomerTestDeps();
      final old = orderJob(status: 'unavailable');
      await pumpOrder(tester, deps, old);
      expect(find.byKey(const Key('ord_view_unavailable')), findsOneWidget);
      expect(find.text('No courier available right now'), findsOneWidget);
      expect(find.byKey(const Key('ord_cancel')), findsNothing);

      final fresh = orderJob(id: 'new-job-77', status: 'pending');
      deps.marketplace.nextBookedJob = fresh;
      deps.marketplace.nextStatus = fresh;
      await tester.tap(find.byKey(const Key('ord_retry_booking')));
      await tester.pumpAndSettle();

      final args = deps.marketplace.bookCalls.single.args;
      expect(args['serviceId'], 'svc-1');
      expect(args['userId'], 'customer-jwt');
      expect(args['latitude'], 30.05);
      expect(args['longitude'], 31.24);
      expect(args['destinationLatitude'], 30.06);
      expect(args['destinationLongitude'], 31.22);
      expect(args['paymentMethod'], 'cod');
      expect(args['pickupAddressNote'], 'Beside the kiosk');
      expect(args['destinationAddressNote'], 'Zamalek, 26th of July St');
      expect(find.text('We sent your order again.'), findsOneWidget);
      expect(find.byKey(const Key('ord_view_searching')), findsOneWidget);

      // Polls the new job.
      await tester.pump(const Duration(seconds: 5));
      expect(deps.marketplace.statusCalls.last, 'new-job-77');
      await unmountOrder(tester, deps);
    });

    testWidgets('retry failure: notice, stays unavailable', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextBookError = apiError();
      await pumpOrder(tester, deps, orderJob(status: 'unavailable'));
      await tester.tap(find.byKey(const Key('ord_retry_booking')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byKey(const Key('ord_view_unavailable')), findsOneWidget);
      await unmountOrder(tester, deps);
    });
  });
}
