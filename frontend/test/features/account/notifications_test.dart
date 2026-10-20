import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/features/account/notifications/notifications_page.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:provider/provider.dart';

import 'account_harness.dart';

class RecordedLinks {
  final List<String> opened = [];

  NotificationLinks get links => NotificationLinks(
        openOrders: (_) => opened.add('orders'),
        openTicket: (_, id, {required resolved}) =>
            opened.add('ticket:$id:$resolved'),
        openTickets: (_) => opened.add('tickets'),
      );
}

Future<(FakeFeed, RecordedLinks, AccountTestDeps)> _pump(
    WidgetTester tester, List<NotificationModel> list,
    {String role = 'user', Locale locale = en, FakeFeed? feed}) async {
  final f = feed ?? (FakeFeed()..notifications = list);
  final links = RecordedLinks();
  final deps = AccountTestDeps(
      auth:
          FakeAuthFlow(user: FakeAuthFlow.customer(role: role), token: 'jwt'));
  deps.extra.add(ChangeNotifierProvider<NotificationsProvider>.value(value: f));
  await pumpAccount(
      tester, deps, NotificationsPage(links: links.links, now: () => now),
      locale: locale);
  return (f, links, deps);
}

void main() {
  group('rules', () {
    test('only customers get links, and only to customer screens', () {
      for (final type in kOrderNotificationTypes) {
        expect(notificationTarget(notif('1', type), 'user').kind,
            NotificationTargetKind.orders);
      }
      for (final role in ['employee', 'owner', null]) {
        for (final type in [
          'job_accepted',
          'ticket_resolved',
          'job_offer',
          'kyc_rejected',
          'payout_completed'
        ]) {
          expect(notificationTarget(notif('1', type), role),
              NotificationTarget.none,
              reason: '$role / $type');
        }
      }
      for (final type in ['job_offer', 'kyc_approved', 'payout_sent', 'x']) {
        expect(notificationTarget(notif('1', type), 'user'),
            NotificationTarget.none);
      }
    });

    test('ticket links carry the ticket id from the body', () {
      expect(
          notificationTarget(
              notif('1', 'ticket_resolved',
                  body: 'Your ticket (tkt-42) has been resolved: refunded'),
              'user'),
          const NotificationTarget(NotificationTargetKind.ticket, 'tkt-42'));
      expect(
          notificationTarget(
              notif('1', 'ticket_assigned',
                  body: 'Sara has joined your ticket (abc-123)'),
              'user'),
          const NotificationTarget(NotificationTargetKind.ticket, 'abc-123'));
      expect(
          notificationTarget(
              notif('1', 'ticket_resolved', body: 'Done'), 'user'),
          const NotificationTarget(NotificationTargetKind.tickets));
      expect(ticketIdFromBody('see ticket-77 now'), 'ticket-77');
    });

    test('copy: localized for known types, server text otherwise', () {
      final en = AppLocalizationsEn();
      final ar = AppLocalizationsAr();
      expect(notificationCopy(en, notif('1', 'job_accepted')),
          ('A courier accepted your order', 'Follow it from the order page.'));
      expect(notificationCopy(ar, notif('1', 'job_accepted')).$1,
          'مندوب قبل طلبك');
      expect(
          notificationCopy(
              en,
              notif('1', 'ticket_resolved',
                  body: 'Your ticket (t1) has been resolved: Refund sent')),
          ('Your complaint was resolved', 'Refund sent'));
      expect(notificationCopy(en, notif('1', 'system', title: 'Hi', body: 'B')),
          ('Hi', 'B'));
    });

    test('groupByDay keeps order and splits by local day', () {
      final a = notif('a', 'x', at: DateTime(2026, 10, 19, 10));
      final b = notif('b', 'x', at: DateTime(2026, 10, 19, 9));
      final c = notif('c', 'x', at: DateTime(2026, 10, 18, 23));
      final groups = groupByDay([a, b, c]);
      expect(groups.length, 2);
      expect(groups[0].$1, DateTime(2026, 10, 19));
      expect(groups[0].$2.map((n) => n.id), ['a', 'b']);
      expect(groups[1].$2.map((n) => n.id), ['c']);
    });
  });

  group('page', () {
    List<NotificationModel> fresh() => [
          notif('n1', 'job_accepted'),
          notif('n2', 'ticket_resolved',
              read: true,
              at: now.subtract(const Duration(hours: 3)),
              body: 'Your ticket (tkt-9) has been resolved: Refund sent'),
          notif('n3', 'job_cancelled', at: DateTime(2026, 10, 18, 20)),
          notif('n4', 'job_offer', at: DateTime(2026, 10, 10, 9), read: true),
        ];
    late List<NotificationModel> list;
    setUp(() => list = fresh());

    testWidgets('day groups, relative times, unread dots', (tester) async {
      await _pump(tester, list);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Oct 10, 2026'), findsOneWidget);
      expect(find.text('5 min ago'), findsOneWidget);
      expect(find.text('3 h ago'), findsOneWidget);
      expect(find.byKey(const Key('ntf_unread_dot')), findsNWidgets(2));
      expect(find.text('Live: new notifications show up here'), findsOneWidget);
    });

    testWidgets('tap marks read and follows the customer link', (tester) async {
      final (feed, links, _) = await _pump(tester, list);
      await tester.tap(find.text('A courier accepted your order'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(feed.calls, contains('markAsRead:n1'));
      expect(links.opened, ['orders']);

      await tester.tap(find.text('Your complaint was resolved'));
      await tester.pump(const Duration(milliseconds: 600));
      // Already read: no second mark.
      expect(feed.calls.where((c) => c == 'markAsRead:n2'), isEmpty);
      expect(links.opened.last, 'ticket:tkt-9:true');

      // A courier type opens nothing.
      await tester.scrollUntilVisible(find.text('Server title'), 100);
      await tester.tap(find.text('Server title'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(links.opened.length, 2);
    });

    testWidgets('an owner tapping an order notification goes nowhere',
        (tester) async {
      final (feed, links, _) = await _pump(tester, list, role: 'owner');
      await tester.tap(find.text('A courier accepted your order'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(feed.calls, contains('markAsRead:n1'));
      expect(links.opened, isEmpty);
    });

    testWidgets('mark all read', (tester) async {
      final (feed, _, _) = await _pump(tester, list);
      await tester.tap(find.byKey(const Key('ntf_mark_all')));
      await tester.pump();
      expect(feed.calls, contains('markAllAsRead'));
      expect(find.byKey(const Key('ntf_unread_dot')), findsNothing);
      expect(find.byKey(const Key('ntf_mark_all')), findsNothing);
    });

    testWidgets('swipe dismisses one', (tester) async {
      final (feed, _, _) = await _pump(tester, list);
      await tester.drag(find.byKey(const Key('ntf_n1')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(feed.calls, contains('dismiss:n1'));
      expect(find.text('A courier accepted your order'), findsNothing);
    });

    testWidgets('clear all asks first', (tester) async {
      final (feed, _, _) = await _pump(tester, list);
      await tester.tap(find.byKey(const Key('ntf_clear_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ntf_clear_cancel')));
      await tester.pumpAndSettle();
      expect(feed.calls, isNot(contains('clearAll')));

      await tester.tap(find.byKey(const Key('ntf_clear_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ntf_clear_confirm')));
      await tester.pumpAndSettle();
      expect(feed.calls, contains('clearAll'));
      expect(find.byKey(const Key('ntf_empty')), findsOneWidget);
    });

    testWidgets('load more', (tester) async {
      final feed = FakeFeed()
        ..notifications = [notif('n1', 'job_accepted')]
        ..hasMore = true;
      await _pump(tester, const [], feed: feed);
      await tester.tap(find.byKey(const Key('ntf_more')));
      await tester.pump();
      expect(feed.calls, contains('loadMore'));
      expect(find.byKey(const Key('ntf_more')), findsNothing);
      expect(find.text('Your order was cancelled'), findsOneWidget);
    });

    testWidgets('first fetch: loader, then the list', (tester) async {
      final feed = FakeFeed()
        ..historyGate = Completer<void>()
        ..nextHistory = [notif('n1', 'job_accepted')];
      usePhone(tester);
      final deps = AccountTestDeps(
          auth: FakeAuthFlow(user: FakeAuthFlow.customer(), token: 'jwt'));
      deps.extra.add(
          ChangeNotifierProvider<NotificationsProvider>.value(value: feed));
      await tester.pumpWidget(accountApp(deps,
          NotificationsPage(links: RecordedLinks().links, now: () => now)));
      await tester.pump();
      expect(find.byKey(const Key('ntf_loading')), findsOneWidget);
      expect(find.byKey(const Key('ntf_empty')), findsNothing);
      feed.historyGate!.complete();
      await tester.pumpAndSettle();
      expect(feed.calls, ['fetchHistory:false']);
      expect(find.text('A courier accepted your order'), findsOneWidget);
    });

    testWidgets('stream down: reconnect; nothing loaded: error with retry',
        (tester) async {
      final feed = FakeFeed()
        ..isConnected = false
        ..error = 'Couldn\'t connect.';
      final (_, _, _) = await _pump(tester, const [], feed: feed);
      expect(find.byKey(const Key('ntf_connection_error')), findsOneWidget);
      expect(find.byKey(const Key('ntf_error')), findsOneWidget);
      await tester.tap(find.text('Reconnect'));
      expect(feed.calls, contains('initSse:jwt'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(feed.calls, contains('fetchHistory:true'));
    });

    testWidgets('offline without error: quiet line', (tester) async {
      final feed = FakeFeed()
        ..isConnected = false
        ..notifications = list;
      await _pump(tester, const [], feed: feed);
      expect(find.text('Not connected: new notifications may be late'),
          findsOneWidget);
    });

    testWidgets('Arabic', (tester) async {
      await _pump(tester, list, locale: ar);
      expect(find.text('النهارده'), findsOneWidget);
      expect(find.text('امبارح'), findsOneWidget);
      expect(find.text('من 5 دقيقة'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('order link closes pushed pages and shows the orders tab',
      (tester) async {
    var shown = 0;
    late NotificationLinks links;
    await tester.pumpWidget(MaterialApp(
      home: OrdersTabScope(
        showOrders: () => shown++,
        child: Builder(builder: (context) {
          links = NotificationLinks.of(context);
          return TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (ctx) => TextButton(
                    onPressed: () => links.openOrders(ctx),
                    child: const Text('link')))),
            child: const Text('shell'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('link'));
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('link'), findsNothing);
    expect(shown, 1);
  });
}
