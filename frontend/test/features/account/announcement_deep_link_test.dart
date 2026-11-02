import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/notifications/announcement_detail_sheet.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/features/account/notifications/notifications_page.dart';
import 'package:frontend/features/account/notifications/push_tap_handler.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/services/local_notifications.dart';
import 'package:frontend/services/notification_tap_router.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:provider/provider.dart';

import 'account_harness.dart';
import 'notifications_test.dart' show RecordedLinks;

class FakePushTapSource implements PushTapSource {
  NotificationModel? initial;
  void Function(NotificationModel)? onOpenedCallback;
  void Function(NotificationModel)? onForegroundCallback;

  @override
  Future<NotificationModel?> initialTap() async => initial;

  @override
  void listen({
    required void Function(NotificationModel n) onOpened,
    required void Function(NotificationModel n) onForeground,
  }) {
    onOpenedCallback = onOpened;
    onForegroundCallback = onForeground;
  }
}

class FakeDisabledNotifier implements LocalNotifier {
  @override
  Future<bool> ensureChannel(
          {required String name, required String description}) async =>
      true;

  @override
  Future<String?> listenTaps(void Function(String payload) onTap) async => null;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async =>
      false; // always fallback to in-app notice
}

void main() {
  group('parseAnnouncementDeepLink table tests', () {
    test('valid /orders/{id} across roles', () {
      const link = '/orders/ord_123';
      expect(parseAnnouncementDeepLink(link, 'user'),
          const NotificationTarget(NotificationTargetKind.job, 'ord_123'));
      expect(parseAnnouncementDeepLink(link, 'owner'),
          const NotificationTarget(NotificationTargetKind.order, 'ord_123'));
      expect(parseAnnouncementDeepLink(link, 'employee'),
          const NotificationTarget(NotificationTargetKind.jobs));
      expect(parseAnnouncementDeepLink(link, 'admin'), NotificationTarget.none);
      expect(parseAnnouncementDeepLink(link, null), NotificationTarget.none);
    });

    test('valid /jobs/{id} across roles', () {
      const link = '/jobs/job-abc.12:x_y';
      expect(
          parseAnnouncementDeepLink(link, 'user'),
          const NotificationTarget(
              NotificationTargetKind.job, 'job-abc.12:x_y'));
      expect(
          parseAnnouncementDeepLink(link, 'owner'),
          const NotificationTarget(
              NotificationTargetKind.order, 'job-abc.12:x_y'));
      expect(parseAnnouncementDeepLink(link, 'employee'),
          const NotificationTarget(NotificationTargetKind.jobs));
      expect(parseAnnouncementDeepLink(link, 'guest'), NotificationTarget.none);
      expect(parseAnnouncementDeepLink(link, null), NotificationTarget.none);
    });

    test('valid /tickets without id across roles', () {
      const link = '/tickets';
      expect(parseAnnouncementDeepLink(link, 'user'),
          const NotificationTarget(NotificationTargetKind.tickets));
      expect(parseAnnouncementDeepLink(link, 'owner'),
          const NotificationTarget(NotificationTargetKind.tickets));
      expect(parseAnnouncementDeepLink(link, 'employee'),
          const NotificationTarget(NotificationTargetKind.tickets));
      expect(parseAnnouncementDeepLink(link, 'other'), NotificationTarget.none);
      expect(parseAnnouncementDeepLink(link, null), NotificationTarget.none);
    });

    test('valid /tickets/{id} across roles', () {
      const link = '/tickets/ticket-42';
      expect(parseAnnouncementDeepLink(link, 'user'),
          const NotificationTarget(NotificationTargetKind.ticket, 'ticket-42'));
      expect(parseAnnouncementDeepLink(link, 'owner'),
          const NotificationTarget(NotificationTargetKind.ticket, 'ticket-42'));
      expect(parseAnnouncementDeepLink(link, 'employee'),
          const NotificationTarget(NotificationTargetKind.ticket, 'ticket-42'));
      expect(parseAnnouncementDeepLink(link, 'other'), NotificationTarget.none);
      expect(parseAnnouncementDeepLink(link, null), NotificationTarget.none);
    });

    test('plan forms across roles (owner only)', () {
      for (final form in [
        '/plan',
        '/plans',
        '/subscription',
        '/subscriptions'
      ]) {
        expect(parseAnnouncementDeepLink(form, 'owner'),
            const NotificationTarget(NotificationTargetKind.plan),
            reason: '$form for owner');
        expect(parseAnnouncementDeepLink(form, 'user'), NotificationTarget.none,
            reason: '$form for user');
        expect(parseAnnouncementDeepLink(form, 'employee'),
            NotificationTarget.none,
            reason: '$form for employee');
        expect(parseAnnouncementDeepLink(form, null), NotificationTarget.none,
            reason: '$form for null');
      }
    });

    test('verification forms across roles (owner and employee only)', () {
      for (final form in ['/verification', '/kyc', '/kyb', '/kye']) {
        expect(parseAnnouncementDeepLink(form, 'owner'),
            const NotificationTarget(NotificationTargetKind.verification),
            reason: '$form for owner');
        expect(parseAnnouncementDeepLink(form, 'employee'),
            const NotificationTarget(NotificationTargetKind.verification),
            reason: '$form for employee');
        expect(parseAnnouncementDeepLink(form, 'user'), NotificationTarget.none,
            reason: '$form for user');
        expect(parseAnnouncementDeepLink(form, null), NotificationTarget.none,
            reason: '$form for null');
      }
    });

    test('boundary: exactly 64-character id is accepted', () {
      final id64 = 'a' * 64;
      expect(parseAnnouncementDeepLink('/orders/$id64', 'owner'),
          NotificationTarget(NotificationTargetKind.order, id64));
      expect(parseAnnouncementDeepLink('/jobs/$id64', 'user'),
          NotificationTarget(NotificationTargetKind.job, id64));
      expect(parseAnnouncementDeepLink('/tickets/$id64', 'employee'),
          NotificationTarget(NotificationTargetKind.ticket, id64));
    });

    test('invalid inputs rejected across all roles', () {
      final invalidLinks = [
        '//evil',
        '//evil.com/orders/123',
        'https://example.com/orders/123',
        'http://example.com/tickets',
        'javascript:alert(1)',
        '/orders/',
        '/jobs/',
        '/orders/a/b',
        '/jobs/a/b',
        '/tickets/a/b',
        '/orders/${'a' * 65}', // over-long id
        '/jobs/${'b' * 65}',
        '/tickets/${'c' * 65}',
        ' /orders/123', // leading whitespace
        '/orders/123 ', // trailing whitespace
        '/orders/1 2', // internal whitespace
        '\t/plan',
        '/subscription\n',
        '/unknown_path',
        '/',
        '',
        'random_text',
      ];

      for (final raw in invalidLinks) {
        for (final role in ['user', 'owner', 'employee', null]) {
          expect(parseAnnouncementDeepLink(raw, role), NotificationTarget.none,
              reason: 'raw=$raw, role=$role');
        }
      }
    });
  });

  group('notificationTarget for admin_announcement', () {
    test('routes deep_link from params', () {
      final notifWithLink = NotificationModel(
        id: 'ann-1',
        type: 'admin_announcement',
        tenantId: 'tenant-1',
        title: 'Title',
        body: 'Body',
        timestamp: DateTime(2026, 11, 1),
        params: {'deep_link': '/plan'},
      );
      expect(notificationTarget(notifWithLink, 'owner'),
          const NotificationTarget(NotificationTargetKind.plan));
      expect(
          notificationTarget(notifWithLink, 'user'), NotificationTarget.none);
    });

    test('returns none without deep_link', () {
      final notifNoLink = NotificationModel(
        id: 'ann-2',
        type: 'admin_announcement',
        tenantId: 'tenant-1',
        title: 'Title',
        body: 'Body',
        timestamp: DateTime(2026, 11, 1),
      );
      expect(notificationTarget(notifNoLink, 'owner'), NotificationTarget.none);
    });
  });

  group('announcement tile widget rendering', () {
    testWidgets(
        'renders campaign icon with gold styling and ellipsis for long text',
        (tester) async {
      final longTitle = 'Very long announcement title ' * 5;
      final longBody = 'Very long announcement body text ' * 10;
      final announcement = NotificationModel(
        id: 'ann-render',
        type: 'admin_announcement',
        tenantId: 't-1',
        title: longTitle,
        body: longBody,
        timestamp: DateTime(2026, 11, 1),
      );

      final feed = FakeFeed()..notifications = [announcement];
      final links = RecordedLinks();
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(
              user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt'));
      deps.extra.add(
          ChangeNotifierProvider<NotificationsProvider>.value(value: feed));

      await pumpAccount(
        tester,
        deps,
        NotificationsPage(links: links.links, now: () => now),
      );

      // Verify campaign icon is rendered
      final iconFinder = find.byIcon(Icons.campaign);
      expect(iconFinder, findsOneWidget);

      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, QdColors.light.onGold);

      // Verify title has maxLines 2 and ellipsis
      final titleFinder = find.text(longTitle);
      expect(titleFinder, findsOneWidget);
      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.maxLines, 2);
      expect(titleWidget.overflow, TextOverflow.ellipsis);

      // Verify body has maxLines 3 and ellipsis
      final bodyFinder = find.text(longBody);
      expect(bodyFinder, findsOneWidget);
      final bodyWidget = tester.widget<Text>(bodyFinder);
      expect(bodyWidget.maxLines, 3);
      expect(bodyWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets(
        'tapping announcement without usable link opens detail sheet; close dismisses it',
        (tester) async {
      final announcement = NotificationModel(
        id: 'ann-sheet',
        type: 'admin_announcement',
        tenantId: 't-1',
        title: 'Platform Maintenance Notice',
        body:
            'Scheduled maintenance will take place tonight from 2 AM to 4 AM UTC.',
        timestamp: DateTime(2026, 11, 1),
      );

      final feed = FakeFeed()..notifications = [announcement];
      final links = RecordedLinks();
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(
              user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt'));
      deps.extra.add(
          ChangeNotifierProvider<NotificationsProvider>.value(value: feed));

      await pumpAccount(
        tester,
        deps,
        NotificationsPage(links: links.links, now: () => now),
      );

      // Tap the announcement tile
      await tester.tap(find.text('Platform Maintenance Notice'));
      await tester.pumpAndSettle();

      // Announcement detail sheet should be open
      expect(find.byType(AnnouncementDetailSheet), findsOneWidget);
      expect(
          find.byKey(const Key('announcement_detail_title')), findsOneWidget);
      expect(
          find.text(
              'Scheduled maintenance will take place tonight from 2 AM to 4 AM UTC.'),
          findsNWidgets(2)); // in list tile + in detail sheet

      // Close button dismisses sheet
      await tester.tap(find.byKey(const Key('announcement_detail_close')));
      await tester.pumpAndSettle();

      expect(find.byType(AnnouncementDetailSheet), findsNothing);
      expect(links.opened, isEmpty);
    });

    testWidgets('tapping announcement with usable link follows the link',
        (tester) async {
      final announcement = NotificationModel(
        id: 'ann-link',
        type: 'admin_announcement',
        tenantId: 't-1',
        title: 'Subscription Discount',
        body: 'Upgrade your plan today.',
        timestamp: DateTime(2026, 11, 1),
        params: {'deep_link': '/plan'},
      );

      final feed = FakeFeed()..notifications = [announcement];
      final links = RecordedLinks();
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(
              user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt'));
      deps.extra.add(
          ChangeNotifierProvider<NotificationsProvider>.value(value: feed));

      await pumpAccount(
        tester,
        deps,
        NotificationsPage(links: links.links, now: () => now),
      );

      await tester.tap(find.text('Subscription Discount'));
      await tester.pumpAndSettle();

      expect(find.byType(AnnouncementDetailSheet), findsNothing);
      expect(links.opened, ['plan']);
    });
  });

  group('push-tap handling for admin_announcement', () {
    testWidgets('push tap with deep link navigates to parsed target',
        (tester) async {
      final tapSource = FakePushTapSource();
      final router = NotificationTapRouter(source: tapSource);
      await router.start();

      final links = RecordedLinks();
      final authFlow = FakeAuthFlow(
          user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authFlow),
          ],
          child: NotificationTapScope(
            router: router,
            child: MaterialApp(
              home: PushTapHandler(
                links: links.links,
                child: const Scaffold(body: Text('Shell Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger push tap with deep link
      final pushWithLink = NotificationModel.fromPushData({
        'id': 'push-ann-1',
        'type': 'admin_announcement',
        'deep_link': '/orders/ord-99',
      }, title: 'Order Update', body: 'Order #99 has an announcement');

      tapSource.onOpenedCallback!(pushWithLink);
      await tester.pumpAndSettle();

      expect(links.opened, ['order:ord-99']);
      expect(find.byType(AnnouncementDetailSheet), findsNothing);
    });

    testWidgets('push tap without deep link opens announcement detail sheet',
        (tester) async {
      final tapSource = FakePushTapSource();
      final router = NotificationTapRouter(source: tapSource);
      await router.start();

      final links = RecordedLinks();
      final authFlow = FakeAuthFlow(
          user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authFlow),
          ],
          child: NotificationTapScope(
            router: router,
            child: MaterialApp(
              home: PushTapHandler(
                links: links.links,
                child: const Scaffold(body: Text('Shell Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger push tap without deep link
      final pushNoLink = NotificationModel.fromPushData({
        'id': 'push-ann-2',
        'type': 'admin_announcement',
      }, title: 'System Notice', body: 'Important announcement details here.');

      tapSource.onOpenedCallback!(pushNoLink);
      await tester.pumpAndSettle();

      expect(links.opened, isEmpty);
      expect(find.byType(AnnouncementDetailSheet), findsOneWidget);
      expect(
          find.byKey(const Key('announcement_detail_title')), findsOneWidget);
      expect(find.text('Important announcement details here.'), findsOneWidget);
    });

    testWidgets(
        'foreground announcement without link falls back to notice with View action opening sheet',
        (tester) async {
      final tapSource = FakePushTapSource();
      final router = NotificationTapRouter(
        source: tapSource,
        display: FakeDisabledNotifier(), // cannot show system notification
      );
      await router.start();

      final links = RecordedLinks();
      final authFlow = FakeAuthFlow(
          user: FakeAuthFlow.customer(role: 'owner'), token: 'jwt');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authFlow),
          ],
          child: NotificationTapScope(
            router: router,
            child: MaterialApp(
              home: PushTapHandler(
                links: links.links,
                child: const Scaffold(body: Text('Shell Content')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deliver foreground announcement
      final fcmAnnouncement = NotificationModel.fromPushData({
        'id': 'push-fg-ann',
        'type': 'admin_announcement',
      }, title: 'Foreground Notice', body: 'Body in foreground');

      tapSource.onForegroundCallback!(fcmAnnouncement);
      await tester.pumpAndSettle();

      // Verify SnackBar notice is displayed with "View" action
      expect(find.byKey(const Key('ntf_push_foreground')), findsOneWidget);
      final viewButton = find.text('View');
      expect(viewButton, findsOneWidget);

      // Tapping "View" opens the detail sheet
      await tester.tap(viewButton);
      await tester.pumpAndSettle();

      expect(find.byType(AnnouncementDetailSheet), findsOneWidget);
      expect(find.text('Foreground Notice'), findsOneWidget);
    });
  });
}
