import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/customer_shell.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/services/local_notifications.dart';
import 'package:frontend/services/notification_tap_router.dart';

import '../customer/customer_harness.dart' as cust;
import 'notification_job_links_test.dart' show FakeTapSource;

// PUSH-FCM item 4: receiving. Payload parsing (`event_type` first), the
// foreground push as a local notification on qd_default plus the in-app
// list, and its tap following the FE-BE-GAPS links.

class FakeDisplay implements LocalNotifier {
  FakeDisplay({this.canShow = true, this.launchPayload});

  bool canShow;
  String? launchPayload;
  final shown = <({int id, String title, String body, String payload})>[];
  void Function(String payload)? tap;

  @override
  Future<bool> show(
      {required int id,
      required String title,
      required String body,
      required String payload}) async {
    if (!canShow) return false;
    shown.add((id: id, title: title, body: body, payload: payload));
    return true;
  }

  @override
  Future<String?> listenTaps(void Function(String payload) onTap) async {
    tap = onTap;
    return launchPayload;
  }

  @override
  Future<bool> ensureChannel(
          {required String name, required String description}) async =>
      true;

  @override
  Future<bool> openAppSettings() async => true;
}

void main() {
  group('payload parsing', () {
    test('event_type first, then type, then system', () {
      expect(
          NotificationModel.fromPushData(
              {'type': 'legacy', 'event_type': 'job_delivered'}).type,
          'job_delivered');
      expect(NotificationModel.fromPushData({'type': 'job_booked'}).type,
          'job_booked');
      expect(
          NotificationModel.fromPushData(
              {'type': 'job_booked', 'event_type': ' '}).type,
          'job_booked');
      expect(NotificationModel.fromPushData({}).type, 'system');
      // SSE and history items carry event_type too.
      expect(
          NotificationModel.fromJson(
              {'id': 'a', 'type': 'x', 'event_type': 'job_picked_up'}).type,
          'job_picked_up');
    });

    test('the server push data (PUSH-BE) as the app reads it', () {
      final m = NotificationModel.fromPushData({
        'id': 'n-7',
        'type': 'job_cancelled',
        'event_type': 'job_cancelled',
        'tenant_id': 'owner-1',
        'job_id': 'job-9',
      }, title: 'Job Cancelled', body: 'Your job was cancelled.');
      expect(m.id, 'n-7');
      expect(m.type, 'job_cancelled');
      expect(m.tenantId, 'owner-1');
      expect(m.jobId, 'job-9');
      expect(m.title, 'Job Cancelled');
    });

    test('local notification payload round trip; foreign payloads ignored',
        () {
      final back = decodePushPayload(encodePushPayload(
          NotificationModel.fromPushData(
              {'id': 'n1', 'type': 'job_picked_up', 'job_id': 'j1'},
              title: 'T',
              body: 'B')))!;
      expect(back.id, 'n1');
      expect(back.type, 'job_picked_up');
      expect(back.jobId, 'j1');
      expect(back.title, 'T');
      expect(back.body, 'B');
      expect(decodePushPayload('not json'), isNull);
      expect(decodePushPayload('[1]'), isNull);
      expect(decodePushPayload(null), isNull);
    });
  });

  group('router', () {
    test('foreground push → onForeground (list) and pending for the shell',
        () async {
      final got = <NotificationModel>[];
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src, onForeground: got.add);
      await router.start();
      src.foreground!(NotificationModel.fromPushData({'id': 'a'}));
      expect(got.single.id, 'a');
      expect(router.takeForeground()?.id, 'a');
    });

    test('a tap on our local notification becomes a tap', () async {
      final display = FakeDisplay();
      final router =
          NotificationTapRouter(source: FakeTapSource(), display: display);
      await router.start();
      display.tap!(encodePushPayload(NotificationModel.fromPushData(
          {'id': 'b', 'type': 'job_delivered', 'job_id': 'j2'})));
      expect(router.takeTap()?.jobId, 'j2');
    });

    test('app launched from our local notification (it was killed)',
        () async {
      final display = FakeDisplay(
          launchPayload: encodePushPayload(NotificationModel.fromPushData(
              {'id': 'c', 'type': 'job_booked', 'job_id': 'j3'})));
      final router =
          NotificationTapRouter(source: FakeTapSource(), display: display);
      await router.start();
      expect(router.takeTap()?.jobId, 'j3');
    });
  });

  group('in-app list', () {
    test('addFromPush lists it once and counts it unread', () {
      final p = NotificationsProvider(
          ApiClient(baseUrl: 'https://ci.local/api/v1'));
      final n = NotificationModel.fromPushData(
          {'id': 'p1', 'type': 'job_accepted', 'job_id': 'j'},
          title: 't', body: 'b');
      p.addFromPush(n);
      p.addFromPush(NotificationModel.fromPushData({'id': 'p1'}));
      p.addFromPush(NotificationModel.fromPushData({'type': 'no-id'}));
      expect(p.notifications.map((e) => e.id), ['p1']);
      expect(p.unreadCount, 1);
      p.dispose();
    });
  });

  group('customer shell, app open', () {
    Future<(cust.CustomerTestDeps, FakeTapSource)> pump(
        WidgetTester tester, FakeDisplay display) async {
      cust.usePhone(tester);
      final deps = cust.CustomerTestDeps();
      deps.marketplace.nextStatus = cust.job(id: 'job-5');
      final src = FakeTapSource();
      final router = NotificationTapRouter(source: src, display: display);
      await router.start();
      await tester.pumpWidget(NotificationTapScope(
          router: router,
          child: cust.customerApp(deps, const CustomerShell())));
      await tester.pumpAndSettle();
      return (deps, src);
    }

    testWidgets(
        'foreground push → system notification in the app language; '
        'its tap opens that order', (tester) async {
      final display = FakeDisplay();
      final (deps, src) = await pump(tester, display);
      src.foreground!(NotificationModel.fromPushData(
          {'id': 'n-1', 'event_type': 'job_picked_up', 'job_id': 'job-5'},
          title: 'Courier Picked Up',
          body: 'Your package was picked up and is heading to the destination.'));
      await tester.pumpAndSettle();
      final shown = display.shown.single;
      expect(shown.title, 'Your order was picked up');
      expect(shown.body, 'The courier has it and is on the way to the drop-off.');
      expect(find.byKey(const Key('ntf_push_foreground')), findsNothing,
          reason: 'no in-app notice when the system shows it');
      expect(deps.nav.openedOrders, isEmpty);

      display.tap!(shown.payload);
      await tester.pumpAndSettle();
      expect(deps.nav.openedOrders.single.$1.id, 'job-5');
    });

    testWidgets('a repeat of the same notification replaces it (same id)',
        (tester) async {
      final display = FakeDisplay();
      final (_, src) = await pump(tester, display);
      for (var i = 0; i < 2; i++) {
        src.foreground!(NotificationModel.fromPushData(
            {'id': 'n-2', 'type': 'job_accepted', 'job_id': 'job-5'}));
        await tester.pumpAndSettle();
      }
      expect(display.shown, hasLength(2));
      expect(display.shown[0].id, display.shown[1].id);
    });

    testWidgets('cannot show a system notification → the in-app notice',
        (tester) async {
      final display = FakeDisplay(canShow: false);
      final (deps, src) = await pump(tester, display);
      src.foreground!(NotificationModel.fromPushData(
          {'id': 'n-3', 'type': 'job_picked_up', 'job_id': 'job-5'}));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ntf_push_foreground')), findsOneWidget);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(deps.nav.openedOrders.single.$1.id, 'job-5');
    });
  });
}
