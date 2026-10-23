import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/task_page.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'courier_harness.dart';

String _money(num v) => QdMoney.format(courierEn(), v);

Future<CourierTestDeps> _pump(WidgetTester tester, Job job,
    {CourierTestDeps? deps}) async {
  usePhone(tester);
  final d = deps ?? CourierTestDeps();
  d.jobs.seed([job]);
  await pumpCourier(tester, d, const CourierTaskPage());
  await tester.pumpAndSettle();
  return d;
}

/// Captures Clipboard.setData calls.
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  group('one primary action by phase', () {
    testWidgets('heading to pickup: confirm the pickup', (tester) async {
      final deps =
          await _pump(tester, courierJob(subStatus: 'heading_to_pickup'));
      expect(find.byKey(const Key('courier_action_pickup')), findsOneWidget);
      expect(find.byKey(const Key('courier_action_deliver')), findsNothing);
      expect(find.text('Going to pickup'), findsOneWidget);

      deps.jobs.jobsAfterAction = [courierJob(subStatus: 'picked_up')];
      await tester.tap(find.byKey(const Key('courier_action_pickup')));
      await tester.pumpAndSettle();
      expect(deps.jobs.calls.single.name, 'pickup');
      expect(
          find.text('Pickup recorded. Head to the drop-off.'), findsOneWidget);
      expect(deps.jobs.fetchCalls, 2);
      expect(find.byKey(const Key('courier_action_deliver')), findsOneWidget);
    });

    testWidgets('pickup 409: already picked up, then the server state',
        (tester) async {
      final deps =
          await _pump(tester, courierJob(subStatus: 'heading_to_pickup'));
      deps.jobs.nextActionError = courierApiError(409, 'job already picked up');
      deps.jobs.nextJobs = [courierJob(subStatus: 'picked_up')];
      await tester.tap(find.byKey(const Key('courier_action_pickup')));
      await tester.pumpAndSettle();
      expect(find.text('This order is already marked as picked up.'),
          findsOneWidget);
      expect(deps.jobs.fetchCalls, 2);
      expect(find.byKey(const Key('courier_action_deliver')), findsOneWidget);
    });

    testWidgets('pickup 403: no longer yours', (tester) async {
      final deps =
          await _pump(tester, courierJob(subStatus: 'heading_to_pickup'));
      deps.jobs.nextActionError = courierApiError(403, 'access denied');
      await tester.tap(find.byKey(const Key('courier_action_pickup')));
      await tester.pumpAndSettle();
      expect(find.text('This order is no longer assigned to you.'),
          findsOneWidget);
    });

    testWidgets('picked up, cash order: delivered with the amount',
        (tester) async {
      await _pump(tester, courierJob(subStatus: 'picked_up', agreed: 40));
      expect(find.text('Delivered, collected ${_money(40)}'), findsOneWidget);
      expect(find.text('Picked up'), findsOneWidget);
    });

    testWidgets('an older job without a phase delivers too', (tester) async {
      await _pump(tester, courierJob());
      expect(find.byKey(const Key('courier_action_deliver')), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
    });

    testWidgets('awaiting a price: no primary action', (tester) async {
      await _pump(
          tester,
          courierJob(
              status: 'awaiting_price_response',
              proposalExpiresAt: courierNow.add(const Duration(minutes: 3))));
      expect(find.byKey(const Key('courier_action_deliver')), findsNothing);
      expect(find.byKey(const Key('courier_action_pickup')), findsNothing);
      expect(find.byKey(const Key('courier_negotiation_none')), findsOneWidget);
    });
  });

  group('complete', () {
    testWidgets('cash order: confirm collects the cash at the price',
        (tester) async {
      final deps = await _pump(tester, courierJob(subStatus: 'picked_up'));
      await tester.tap(find.byKey(const Key('courier_action_deliver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_complete_sheet')), findsOneWidget);
      expect(
          find.text(
              'Confirm you handed it over and collected ${_money(42)} cash.'),
          findsOneWidget);

      deps.jobs.jobsAfterAction = [courierJob(status: 'completed')];
      await tester.tap(find.byKey(const Key('courier_complete_confirm')));
      await tester.pumpAndSettle();
      final call = deps.jobs.calls.single;
      expect(call.name, 'complete');
      expect(call.args['cash'], isTrue);
      expect(call.args['amount'], isNull);
      expect(deps.location.calls.map((c) => c.name), contains('stop'));
      expect(find.text('Order delivered. Well done!'), findsOneWidget);
      expect(find.byKey(const Key('courier_task_idle')), findsOneWidget);
    });

    testWidgets('a different amount is sent; a bad one is refused',
        (tester) async {
      final deps = await _pump(tester, courierJob(subStatus: 'picked_up'));
      await tester.tap(find.byKey(const Key('courier_action_deliver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('courier_complete_different')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('courier_complete_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the amount you collected, like 42.'),
          findsOneWidget);
      expect(deps.jobs.calls, isEmpty);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('courier_complete_amount')),
              matching: find.byType(EditableText)),
          '45.5');
      await tester.tap(find.byKey(const Key('courier_complete_confirm')));
      await tester.pumpAndSettle();
      expect(deps.jobs.calls.single.args['amount'], 45.5);
      expect(deps.jobs.calls.single.args['cash'], isTrue);
    });

    testWidgets('a failure keeps the sheet open with the error',
        (tester) async {
      final deps = await _pump(tester, courierJob(subStatus: 'picked_up'));
      deps.jobs.nextActionError = courierApiError(503, 'down');
      await tester.tap(find.byKey(const Key('courier_action_deliver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('courier_complete_confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_complete_sheet')), findsOneWidget);
      expect(find.byKey(const Key('courier_complete_error')), findsOneWidget);
      expect(deps.location.calls.map((c) => c.name), isNot(contains('stop')));
    });

    testWidgets('non-cash order: delivered only, no cash flag', (tester) async {
      final deps = await _pump(
          tester, courierJob(subStatus: 'picked_up', payment: 'wallet'));
      expect(find.text('Delivered'), findsOneWidget);
      await tester.tap(find.byKey(const Key('courier_action_deliver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_complete_different')), findsNothing);
      await tester.tap(find.byKey(const Key('courier_complete_confirm')));
      await tester.pumpAndSettle();
      expect(deps.jobs.calls.single.args['cash'], isFalse);
    });
  });

  group('cancellation request', () {
    testWidgets('reason required, sent, then the pending banner',
        (tester) async {
      final deps = await _pump(tester, courierJob(subStatus: 'picked_up'));
      await tester.tap(find.byKey(const Key('courier_request_cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_cancel_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const Key('courier_cancel_confirm')));
      await tester.pumpAndSettle();
      expect(deps.jobs.calls, isEmpty);

      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('courier_cancel_reason')),
              matching: find.byType(EditableText)),
          'Bike broke down');
      await tester.pump();
      deps.jobs.jobsAfterAction = [
        courierJob(subStatus: 'picked_up', requestStatus: 'pending')
      ];
      await tester.tap(find.byKey(const Key('courier_cancel_confirm')));
      await tester.pumpAndSettle();
      expect(deps.jobs.calls.single.name, 'requestCancellation');
      expect(deps.jobs.calls.single.args['reason'], 'Bike broke down');
      expect(find.text('Request sent to your company owner.'), findsOneWidget);
      expect(find.byKey(const Key('courier_cancel_pending')), findsOneWidget);
      expect(find.byKey(const Key('courier_request_cancel')), findsNothing);
    });

    testWidgets('a rejected request is shown and can be asked again',
        (tester) async {
      await _pump(tester,
          courierJob(subStatus: 'picked_up', requestStatus: 'rejected'));
      expect(find.byKey(const Key('courier_cancel_rejected')), findsOneWidget);
      expect(find.byKey(const Key('courier_request_cancel')), findsOneWidget);
    });
  });

  group('recipient and map', () {
    testWidgets('recipient with phone: copy number and chat', (tester) async {
      final copied = _mockClipboard(tester);
      final deps = await _pump(
          tester,
          courierJob(
            subStatus: 'picked_up',
            recipient: const JobRecipient(
                name: 'Mahmoud', phone: '+201012345678', notes: 'Ring twice'),
          ));
      expect(find.text('Mahmoud'), findsOneWidget);
      expect(find.text('Notes: Ring twice'), findsOneWidget);
      expect(find.text('+201012345678'), findsOneWidget);
      await _tapVisible(
          tester, find.byKey(const Key('courier_recipient_call')));
      expect(copied, ['+201012345678']);
      expect(find.byKey(const Key('courier_phone_copied')), findsOneWidget);
      await _tapVisible(
          tester, find.byKey(const Key('courier_recipient_chat')));
      expect(deps.nav.opened, ['chat:a1b2c3d4e5f6']);
    });

    testWidgets('no phone: no call button, generic name', (tester) async {
      await _pump(tester, courierJob(subStatus: 'picked_up'));
      expect(find.byKey(const Key('courier_recipient_call')), findsNothing);
      expect(find.text('Customer'), findsOneWidget);
    });

    testWidgets('open in maps copies the next stop', (tester) async {
      final copied = _mockClipboard(tester);
      await _pump(tester, courierJob(subStatus: 'heading_to_pickup'));
      await tester.tap(find.byKey(const Key('courier_open_maps')));
      await tester.pumpAndSettle();
      expect(copied, ['30.044400,31.235700']);
    });

    testWidgets('customer sees your location while the job is tracked',
        (tester) async {
      final deps = CourierTestDeps();
      await _pump(tester, courierJob(id: 'job-7', subStatus: 'picked_up'),
          deps: deps);
      // The controller started tracking this job on refresh.
      expect(deps.location.activeJobId, 'job-7');
      expect(find.byKey(const Key('courier_sharing_live')), findsOneWidget);
    });

    testWidgets('location denied: chip and settings banner', (tester) async {
      final deps = CourierTestDeps();
      deps.location.status = LocationSharingStatus.permissionDenied;
      await _pump(tester, courierJob(subStatus: 'picked_up'), deps: deps);
      expect(find.byKey(const Key('courier_sharing_off')), findsOneWidget);
      expect(
          find.byKey(const Key('courier_active_permission')), findsOneWidget);
    });

    testWidgets('ETA snapshot by phase, package details', (tester) async {
      final j = Job(
        id: 'eta',
        ownerId: 'o',
        userId: 'u',
        serviceId: 's',
        status: 'active',
        subStatus: 'heading_to_pickup',
        estimatedDurationMinutes: 9,
        location: JobLocation(latitude: 30.04, longitude: 31.23),
        paymentMethod: 'cod',
        suggestedPrice: 42,
        packageDetails: const JobPackageDetails(size: 'large'),
      );
      await _pump(tester, j);
      expect(find.text('Estimate: about 9 min to the pickup'), findsOneWidget);
      expect(find.text('Package: Large'), findsOneWidget);
    });

    testWidgets('several running tasks: switch between them', (tester) async {
      usePhone(tester);
      final deps = CourierTestDeps();
      deps.jobs.seed([
        courierJob(id: 'job-a', subStatus: 'picked_up'),
        courierJob(
            id: 'job-b',
            status: 'awaiting_price_response',
            dropNote: 'Dokki',
            proposalExpiresAt: courierNow.add(const Duration(minutes: 3))),
      ]);
      await pumpCourier(tester, deps, const CourierTaskPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_other_jobs')), findsOneWidget);
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('courier_running_job-b')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier_negotiation_none')), findsOneWidget);
    });
  });
}
