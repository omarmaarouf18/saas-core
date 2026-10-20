import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/account_page.dart';
import 'package:frontend/features/account/my_details_page.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/features/account/notifications/notifications_page.dart';
import 'package:frontend/features/account/saved_addresses_page.dart';
import 'package:frontend/features/account/security_page.dart';
import 'package:frontend/features/account/support/tickets_page.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/support_ticket.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:provider/provider.dart';

import '../customer/customer_harness.dart' as cust;
import 'account_harness.dart';

// Golden snapshots of the FE-AUTH-ACCOUNT customer account, notifications
// and support pages at 360x800, light, AR-RTL and EN-LTR, Plex font.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/account/account_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

FakeAuthFlow _auth(Locale l, {bool suspended = false}) => FakeAuthFlow(
      token: 'jwt',
      user: FakeAuthFlow.customer(
        accountStatus: suspended ? 'suspended' : 'active',
        suspensionReason: suspended
            ? _t(l, 'Unpaid fees on two orders', 'رسوم متأخرة على طلبين')
            : null,
        addresses: [
          _t(l, 'Home, 12 Tahrir St, Dokki', 'البيت، 12 شارع التحرير، الدقي'),
          _t(l, 'Work, Smart Village B7', 'الشغل، القرية الذكية B7'),
        ],
      ).copyWith(username: _t(l, 'Mona Ali', 'منى علي')),
    );

List<NotificationModel> _notifications(Locale l) => [
      notif('n1', 'job_accepted'),
      notif('n2', 'ticket_resolved',
          at: now.subtract(const Duration(hours: 2)),
          body: _t(l, 'Your ticket (tkt-9) has been resolved: Refund sent',
              'Your ticket (tkt-9) has been resolved: رجعنالك الفلوس')),
      notif('n3', 'job_completed',
          read: true, at: DateTime(2026, 10, 18, 20, 15)),
      notif('n4', 'job_unavailable',
          read: true, at: DateTime(2026, 10, 18, 9, 40)),
    ];

typedef _Account = (
  Widget Function(Locale),
  Future<void> Function(WidgetTester)
);

Future<void> _none(WidgetTester tester) async {}

final Map<String, _Account> _accountScreens = {
  'account': ((_) => const AccountPage(), _none),
  'details': ((_) => const MyDetailsPage(), _none),
  'addresses': ((_) => const SavedAddressesPage(), _none),
  'security': ((_) => const SecurityPage(), _none),
  'email_change': (
    (_) => const MyDetailsPage(),
    (tester) async {
      await tester.tap(find.byKey(const Key('details_change_email')));
      await tester.pumpAndSettle();
      await typeInto(tester, 'email_change_input', 'mona.ali@example.com');
      await tester.tap(find.byKey(const Key('email_change_send')));
      await tester.pumpAndSettle();
    }
  ),
  'notifications': (
    (_) => NotificationsPage(
        now: () => now,
        links: NotificationLinks(
            openOrders: (_) {},
            openTicket: (_, __, {required resolved}) {},
            openTickets: (_) {})),
    _none
  ),
};

List<SupportTicket> _tickets(Locale l) => [
      SupportTicket(
        id: 'tkt-1a2b3c4d',
        customerId: 'user-1',
        status: 'pending',
        contextId: _t(
            l,
            'Job #a1b2c3d4e5f6 - Late order: It arrived two hours late',
            'Job #a1b2c3d4e5f6 - الطلب اتأخر: وصل متأخر ساعتين'),
        createdAt: DateTime(2026, 10, 19, 14, 5),
      ),
      SupportTicket(
        id: 'tkt-9z8y7x6w',
        customerId: 'user-1',
        status: 'resolved',
        contextId:
            _t(l, 'Wrong charge: I paid twice', 'فلوس زيادة: دفعت مرتين'),
        resolutionNote: _t(l, 'Refund sent', 'رجعنالك الفلوس'),
        createdAt: DateTime(2026, 10, 12, 10, 0),
      ),
    ];

final Map<String, Future<void> Function(WidgetTester)> _supportScreens = {
  'tickets': _none,
  'complaint': (tester) async {
    await tester.tap(find.byKey(const Key('tickets_new')));
    await tester.pumpAndSettle();
  },
  'ticket_chat': (tester) async {
    await tester.tap(find.byKey(const Key('ticket_tkt-1a2b3c4d')));
    await tester.pumpAndSettle();
  },
};

void main() {
  setUpAll(cust.loadPlexFont);

  _accountScreens.forEach((name, entry) {
    final (build, setup) = entry;
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN account $name $dir', (tester) async {
        final deps = AccountTestDeps(auth: _auth(locale))
          ..auth.devOtp = '482913';
        deps.extra.add(ChangeNotifierProvider<NotificationsProvider>.value(
            value: FakeFeed()..notifications = _notifications(locale)));
        await pumpAccount(tester, deps, build(locale), locale: locale);
        await setup(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/acct_${name}_${dir}_360x800.png'),
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  for (final locale in bothLocales) {
    final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
    testWidgets('GOLDEN account suspended $dir', (tester) async {
      final deps = AccountTestDeps(auth: _auth(locale, suspended: true));
      await pumpAccount(tester, deps, const AccountPage(), locale: locale);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/acct_suspended_${dir}_360x800.png'),
      );
    });
  }

  _supportScreens.forEach((name, setup) {
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN support $name $dir', (tester) async {
        cust.usePhone(tester);
        final deps = cust.CustomerTestDeps();
        deps.chat.nextTickets = _tickets(locale);
        deps.marketplace.nextJobs = [
          cust.job(
              id: 'a1b2c3d4e5f6',
              status: 'active',
              createdAt: DateTime(2026, 10, 19, 14, 5)),
          cust.job(
              id: 'f6e5d4c3b2a1',
              status: 'completed',
              createdAt: DateTime(2026, 10, 18, 11, 40)),
        ];
        deps.chat.nextHistory = [
          ChatMessage(
            id: 'm1',
            channel: 'ticket:tkt-1a2b3c4d',
            senderId: 'user-1',
            senderUsername: 'Mona',
            content: _t(locale, 'My order arrived two hours late.',
                'طلبي وصل متأخر ساعتين.'),
            type: 'message',
          ),
          ChatMessage(
            id: 'm2',
            channel: 'ticket:tkt-1a2b3c4d',
            senderId: 'agent-1',
            senderUsername: 'Sara',
            content: _t(locale, 'Sorry about that. Checking it now.',
                'آسفين جداً. بنراجعها دلوقتي.'),
            type: 'message',
          ),
          ChatMessage(
            id: 'm3',
            channel: 'ticket:tkt-1a2b3c4d',
            senderId: 'user-1',
            senderUsername: 'Mona',
            content: 'receipt.pdf',
            type: 'attachment',
            attachmentUrl: 'https://files.invalid/receipt.pdf',
            attachmentName: 'receipt.pdf',
            attachmentType: 'application/pdf',
            attachmentSize: 182000,
          ),
        ];
        await tester.pumpWidget(cust.customerApp(
            deps, TicketsPage(now: () => cust.fixedNow),
            locale: locale));
        await tester.pumpAndSettle();
        await setup(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/sup_${name}_${dir}_360x800.png'),
        );
      });
    }
  });
}
