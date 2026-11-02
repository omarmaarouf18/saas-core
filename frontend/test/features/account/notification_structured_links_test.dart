import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/models/notification_model.dart';

void main() {
  NotificationModel n(
    String type, {
    String? jobId,
    Map<String, String>? params,
    String body = '',
  }) =>
      NotificationModel(
        id: 'n-1',
        type: type,
        tenantId: 'tenant-1',
        jobId: jobId,
        title: 'Title',
        body: body,
        timestamp: DateTime(2026, 10, 1),
        params: params,
      );

  group('structured links - tickets', () {
    test('uses params.ticket_id for ticket links', () {
      final withId = n('ticket_resolved', params: {'ticket_id': 'tkt-123'});
      expect(
        notificationTarget(withId, 'user'),
        const NotificationTarget(NotificationTargetKind.ticket, 'tkt-123'),
      );
      expect(
        notificationTarget(withId, 'owner'),
        const NotificationTarget(NotificationTargetKind.ticket, 'tkt-123'),
      );
      expect(
        notificationTarget(withId, 'employee'),
        const NotificationTarget(NotificationTargetKind.ticket, 'tkt-123'),
      );
    });

    test('opens tickets list without params.ticket_id', () {
      final withoutId = n('ticket_resolved', body: 'body mentions ticket (tkt-old) but no params');
      expect(
        notificationTarget(withoutId, 'user'),
        const NotificationTarget(NotificationTargetKind.tickets),
      );
      expect(
        notificationTarget(withoutId, 'owner'),
        const NotificationTarget(NotificationTargetKind.tickets),
      );
      expect(
        notificationTarget(withoutId, 'employee'),
        const NotificationTarget(NotificationTargetKind.tickets),
      );
    });
  });

  group('structured links - owner cancellation and dispute types', () {
    test('uses n.jobId for owner cancellation and dispute', () {
      final req = n('cancellation_requested', jobId: 'job-999');
      expect(
        notificationTarget(req, 'owner'),
        const NotificationTarget(
          NotificationTargetKind.job,
          'job-999',
          NotificationTarget(NotificationTargetKind.order, 'job-999'),
        ),
      );

      final exp = n('cancellation_request_expired', jobId: 'job-888');
      expect(
        notificationTarget(exp, 'owner'),
        const NotificationTarget(
          NotificationTargetKind.job,
          'job-888',
          NotificationTarget(NotificationTargetKind.order, 'job-888'),
        ),
      );

      final disp = n('dispute_resolved', jobId: 'job-777');
      expect(
        notificationTarget(disp, 'owner'),
        const NotificationTarget(
          NotificationTargetKind.job,
          'job-777',
          NotificationTarget(NotificationTargetKind.order, 'job-777'),
        ),
      );
    });

    test('falls back to orders tab when jobId is missing (old history)', () {
      final oldReq = n('cancellation_requested', body: 'mentions job job-old in text');
      expect(
        notificationTarget(oldReq, 'owner'),
        const NotificationTarget(NotificationTargetKind.orders),
      );

      final oldExp = n('cancellation_request_expired');
      expect(
        notificationTarget(oldExp, 'owner'),
        const NotificationTarget(NotificationTargetKind.orders),
      );

      final oldDisp = n('dispute_resolved');
      expect(
        notificationTarget(oldDisp, 'owner'),
        const NotificationTarget(NotificationTargetKind.orders),
      );
    });
  });

  group('structured links - cancellation_resolved variant', () {
    test('variant decline -> current task for courier', () {
      final decline = n('cancellation_resolved', params: {'variant': 'decline'});
      expect(
        notificationTarget(decline, 'employee'),
        const NotificationTarget(NotificationTargetKind.task),
      );
    });

    test('variant accept -> My jobs for courier', () {
      final accept = n('cancellation_resolved', params: {'variant': 'accept'});
      expect(
        notificationTarget(accept, 'employee'),
        const NotificationTarget(NotificationTargetKind.jobs),
      );
    });

    test('unknown or missing variant (push tap) defaults to My jobs, not task page', () {
      // Even if Arabic body or empty body
      final pushTapAr = n(
        'cancellation_resolved',
        body: 'تم قبول طلب الإلغاء', // Arabic text that previously failed English .contains("approved")
      );
      expect(
        notificationTarget(pushTapAr, 'employee'),
        const NotificationTarget(NotificationTargetKind.jobs),
      );

      final pushTapEmpty = n('cancellation_resolved');
      expect(
        notificationTarget(pushTapEmpty, 'employee'),
        const NotificationTarget(NotificationTargetKind.jobs),
      );
    });
  });

  group('role gating strictly preserved', () {
    test('roles only receive links to their own screens', () {
      final courierItem = n('job_offer');
      expect(notificationTarget(courierItem, 'user'), NotificationTarget.none);
      expect(notificationTarget(courierItem, 'owner'), NotificationTarget.none);
      expect(
        notificationTarget(courierItem, 'employee'),
        const NotificationTarget(NotificationTargetKind.task),
      );

      final ownerItem = n('subscription_expired');
      expect(notificationTarget(ownerItem, 'user'), NotificationTarget.none);
      expect(notificationTarget(ownerItem, 'employee'), NotificationTarget.none);
      expect(
        notificationTarget(ownerItem, 'owner'),
        const NotificationTarget(NotificationTargetKind.plan),
      );

      final customerItem = n('job_booked');
      expect(notificationTarget(customerItem, 'employee'),
          const NotificationTarget(NotificationTargetKind.jobs));
      expect(notificationTarget(customerItem, 'user'),
          const NotificationTarget(NotificationTargetKind.orders));
    });

    test('unsupported role gets no links', () {
      expect(notificationTarget(n('ticket_resolved'), 'unknown'), NotificationTarget.none);
      expect(notificationTarget(n('job_offer'), null), NotificationTarget.none);
    });
  });
}
