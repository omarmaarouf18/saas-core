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
        openOrder: (_, id) => opened.add('order:$id'),
        openTeam: (_) => opened.add('team'),
        openPlan: (_) => opened.add('plan'),
        openVerification: (_) => opened.add('verification'),
        openTask: (_) => opened.add('task'),
        openJobs: (_) => opened.add('jobs'),
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
    NotificationTargetKind kind(String type, String? role, {String? body}) =>
        notificationTarget(notif('1', type, body: body ?? ''), role).kind;

    test('customers: order types open My orders, nothing else links', () {
      for (final type in kOrderNotificationTypes) {
        expect(kind(type, 'user'), NotificationTargetKind.orders);
      }
      for (final type in [
        'job_offer',
        'job_alert',
        'kyc_approved',
        'cancellation_requested',
        'payout_sent',
        'x'
      ]) {
        expect(kind(type, 'user'), NotificationTargetKind.none, reason: type);
      }
    });

    test('owners: order detail by job id, orders, team, plan, verification',
        () {
      expect(
          notificationTarget(
              notif('1', 'cancellation_requested',
                  body: 'Courier e1 requested cancellation of job j-42: '
                      'flat tyre. Respond within 15 minutes.'),
              'owner'),
          const NotificationTarget(NotificationTargetKind.order, 'j-42'));
      expect(
          notificationTarget(
              notif('1', 'cancellation_request_expired',
                  body: 'The cancellation request window lapsed with no '
                      'response; courier e1 was unassigned and job abc_9 '
                      'returned to dispatch.'),
              'owner'),
          const NotificationTarget(NotificationTargetKind.order, 'abc_9'));
      expect(kind('dispute_resolved', 'owner', body: 'Refunded.'),
          NotificationTargetKind.orders);
      expect(
          kind('kyc_rejected', 'owner'), NotificationTargetKind.verification);
      expect(
          kind('kyc_approved', 'owner'), NotificationTargetKind.verification);
      expect(
          kind('subscription_expired', 'owner'), NotificationTargetKind.plan);
      expect(kind('employee_added', 'owner'), NotificationTargetKind.team);
      // Courier and customer types never open owner pages.
      for (final type in [
        'job_offer',
        'job_accepted',
        'cancellation_resolved'
      ]) {
        expect(kind(type, 'owner'), NotificationTargetKind.none, reason: type);
      }
    });

    test('couriers: offer / current job, my jobs, verification', () {
      expect(kind('job_offer', 'employee'), NotificationTargetKind.task);
      expect(kind('job_alert', 'employee'), NotificationTargetKind.task);
      expect(
          kind('cancellation_resolved', 'employee',
              body: 'Your cancellation request for job j1 was declined by the '
                  'business owner. You remain assigned.'),
          NotificationTargetKind.task);
      expect(
          kind('cancellation_resolved', 'employee',
              body: 'Your cancellation request for job j1 was approved by the '
                  'business owner. The job has been cancelled.'),
          NotificationTargetKind.jobs);
      expect(kind('dispute_resolved', 'employee'), NotificationTargetKind.jobs);
      expect(kind('kyc_rejected', 'employee'),
          NotificationTargetKind.verification);
      // Owner-only types do nothing for a courier.
      for (final type in [
        'cancellation_requested',
        'subscription_expired',
        'employee_added',
        'account_reactivated'
      ]) {
        expect(kind(type, 'employee'), NotificationTargetKind.none,
            reason: type);
      }
    });

    test('unknown roles get no links at all', () {
      for (final role in ['admin', 'reviewer', null]) {
        for (final type in [
          'job_accepted',
          'ticket_resolved',
          'job_offer',
          'kyc_rejected',
          'cancellation_requested'
        ]) {
          expect(kind(type, role), NotificationTargetKind.none,
              reason: '$role / $type');
        }
      }
    });

    test('job id from the body', () {
      expect(jobIdFromBody('You have an incoming job offer for job 65f1a. '),
          '65f1a');
      expect(jobIdFromBody('No job here'), isNull);
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
      await tester.scrollUntilVisible(find.text('New job offer'), 100);
      await tester.tap(find.text('New job offer'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(links.opened.length, 2);
    });

    testWidgets('an owner tapping a customer order notification goes nowhere',
        (tester) async {
      final (feed, links, _) = await _pump(tester, list, role: 'owner');
      await tester.tap(find.text('A courier accepted your order'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(feed.calls, contains('markAsRead:n1'));
      expect(links.opened, isEmpty);
    });

    testWidgets('owner: cancellation request opens that order', (tester) async {
      final (_, links, _) = await _pump(
          tester,
          [
            notif('o1', 'cancellation_requested',
                body: 'Courier e1 requested cancellation of job j-7: late.'),
            notif('o2', 'kyc_rejected',
                body: 'Your KYB verification was rejected. Reason: blurry'),
          ],
          role: 'owner');
      expect(find.text('A courier asked to cancel a job'), findsOneWidget);
      await tester.tap(find.text('A courier asked to cancel a job'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text("Your verification wasn't accepted"));
      await tester.pump(const Duration(milliseconds: 600));
      expect(links.opened, ['order:j-7', 'verification']);
    });

    testWidgets('courier: an offer opens the Task tab', (tester) async {
      final (_, links, _) = await _pump(
          tester, [notif('c1', 'job_offer', body: 'Offer for job j-1.')],
          role: 'employee');
      expect(find.text('New job offer'), findsOneWidget);
      expect(find.text('Answer it from the Task tab before the time runs out.'),
          findsOneWidget);
      await tester.tap(find.text('New job offer'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(links.opened, ['task']);
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

  Future<NotificationLinks> pumpShell(
      WidgetTester tester, NotificationShellLinks shell) async {
    late NotificationLinks links;
    await tester.pumpWidget(MaterialApp(
      home: NotificationShellScope(
        links: shell,
        child: Builder(builder: (context) {
          links = NotificationLinks.of(context);
          return TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (ctx) => Builder(
                    builder: (ctx) => TextButton(
                        onPressed: () => links.follow(
                            ctx,
                            notificationTarget(
                                notif('x', 'cancellation_requested',
                                    body: 'cancellation of job j-3: x'),
                                'owner')),
                        child: const Text('owner link'))))),
            child: const Text('shell'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('shell'));
    await tester.pumpAndSettle();
    return links;
  }

  testWidgets('order link closes pushed pages and shows the orders tab',
      (tester) async {
    var shown = 0;
    final links = await pumpShell(
        tester, NotificationShellLinks(showOrders: () => shown++));
    final ctx = tester.element(find.text('owner link'));
    links.openOrders!(ctx);
    await tester.pumpAndSettle();
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('owner link'), findsNothing);
    expect(shown, 1);
  });

  testWidgets('owner order link closes pushed pages, then opens the order',
      (tester) async {
    final opened = <String>[];
    await pumpShell(tester, NotificationShellLinks(openOrder: opened.add));
    await tester.tap(find.text('owner link'));
    await tester.pumpAndSettle();
    expect(find.text('owner link'), findsNothing);
    expect(opened, ['j-3']);
  });

  testWidgets('a link the shell does not offer does nothing', (tester) async {
    final links = await pumpShell(tester, const NotificationShellLinks());
    expect(links.openOrders, isNull);
    expect(links.openTask, isNull);
    await tester.tap(find.text('owner link'));
    await tester.pumpAndSettle();
    expect(find.text('owner link'), findsOneWidget);
  });
}
