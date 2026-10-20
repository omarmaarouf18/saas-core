import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/support/new_complaint_sheet.dart';
import 'package:frontend/features/account/support/ticket_rules.dart';
import 'package:frontend/features/account/support/tickets_page.dart';
import 'package:frontend/features/customer/chat/chat_page.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/support_ticket.dart';
import 'package:frontend/ui/qd_ui.dart';

import '../customer/customer_harness.dart';

SupportTicket ticket(String id,
        {String status = 'pending',
        String? context,
        String? note,
        DateTime? at}) =>
    SupportTicket(
      id: id,
      customerId: 'user-1',
      status: status,
      contextId: context,
      resolutionNote: note,
      createdAt: at ?? DateTime(2026, 10, 19, 14, 5),
    );

String _plain(String s) => s.replaceAll(RegExp('[\\u2066-\\u2069]'), '');

Future<void> _pumpTickets(WidgetTester tester, CustomerTestDeps deps,
    {ChatAttachmentPicker? picker, Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(customerApp(
      deps, TicketsPage(now: () => fixedNow, pickAttachment: picker),
      locale: locale));
  await tester.pumpAndSettle();
}

Finder _textPlain(String text) => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && _plain(w.data!) == text);

void main() {
  group('rules', () {
    test('context format round trip, with and without an order', () {
      final withJob = buildTicketContext(
          jobId: 'a1b2c3d4e5', subject: 'Late', description: 'Two: hours');
      expect(withJob, 'Job #a1b2c3d4e5 - Late: Two: hours');
      final p = parseTicketContext(withJob);
      expect((p.jobId, p.subject, p.description),
          ('a1b2c3d4e5', 'Late', 'Two: hours'));

      final plain = parseTicketContext(
          buildTicketContext(subject: 'App', description: 'Crashes'));
      expect((plain.jobId, plain.subject, plain.description),
          (null, 'App', 'Crashes'));
    });

    test('older contexts: bare job id, free text', () {
      expect(parseTicketContext('a1b2c3d4e5f6').jobId, 'a1b2c3d4e5f6');
      expect(parseTicketContext('Something odd').subject, 'Something odd');
      expect(parseTicketContext(null).subject, '');
    });

    test('subject fallbacks and status chips', () {
      final l10n = AppLocalizationsEn();
      expect(ticketSubject(l10n, ticket('abcdef123456', context: 'X: y')), 'X');
      expect(_plain(ticketSubject(l10n, ticket('abcdef123456'))),
          'Complaint #ABCDEF12');
      expect(ticketStatusChip(l10n, 'pending'),
          ('Waiting for a reply', QdTone.warning));
      expect(ticketStatusChip(l10n, 'assigned').$2, QdTone.success);
      expect(ticketStatusChip(l10n, 'resolved').$1, 'Resolved');
      expect(ticketStatusChip(l10n, 'weird').$1, 'Open');
    });
  });

  group('tickets page', () {
    final tickets = [
      ticket('t-open-1',
          context: 'Job #a1b2c3d4e5f6 - Late order: It took two hours'),
      ticket('t-done-1',
          status: 'resolved',
          context: 'Wrong charge: I paid twice',
          note: 'Refund sent'),
    ];

    testWidgets('open and resolved tabs, cards from the context',
        (tester) async {
      final deps = CustomerTestDeps()..chat.nextTickets = tickets;
      await _pumpTickets(tester, deps);
      expect(deps.chat.ticketCalls, 1);
      expect(find.text('Open · 1'), findsOneWidget);
      expect(find.text('Late order'), findsOneWidget);
      expect(find.text('Waiting for a reply'), findsOneWidget);
      expect(_textPlain('About order #QD-A1B2C3D4 · Today · 2:05 PM'),
          findsOneWidget);
      expect(find.text('It took two hours'), findsOneWidget);
      expect(find.byKey(const Key('tickets_hint')), findsOneWidget);
      expect(find.text('Wrong charge'), findsNothing);

      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong charge'), findsOneWidget);
      expect(find.text('Resolution: Refund sent'), findsOneWidget);
      expect(find.byKey(const Key('tickets_hint')), findsNothing);
    });

    testWidgets('loader while empty, then error with retry', (tester) async {
      final deps = CustomerTestDeps();
      deps.chat.ticketsGate = Completer<void>();
      deps.chat.nextTicketsError = 'Service unavailable';
      usePhone(tester);
      await tester.pumpWidget(customerApp(deps, const TicketsPage()));
      await tester.pump();
      expect(find.byKey(const Key('tickets_loading')), findsOneWidget);
      deps.chat.ticketsGate!.complete();
      deps.chat.ticketsGate = null;
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_error')), findsOneWidget);
      deps.chat.nextTicketsError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tickets_hint')), findsOneWidget);
    });

    testWidgets('resolved tab empty state', (tester) async {
      final deps = CustomerTestDeps();
      await _pumpTickets(tester, deps);
      expect(find.text('Open · 0'), findsOneWidget);
      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();
      expect(find.text('No resolved complaints yet'), findsOneWidget);
    });

    testWidgets('a card opens its chat; back reloads the list', (tester) async {
      final deps = CustomerTestDeps()..chat.nextTickets = tickets;
      await _pumpTickets(tester, deps);
      await tester.tap(find.text('Late order'));
      await tester.pumpAndSettle();
      expect(deps.chat.historyCalls, ['ticket:t-open-1']);
      expect(find.byKey(const Key('chat_attach')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(deps.chat.ticketCalls, 2);
    });
  });

  group('new complaint', () {
    Future<void> openSheet(WidgetTester tester, CustomerTestDeps deps) async {
      await _pumpTickets(tester, deps);
      await tester.tap(find.byKey(const Key('tickets_new')));
      await tester.pumpAndSettle();
      expect(find.byType(NewComplaintSheet), findsOneWidget);
    }

    testWidgets(
        'lists recent orders (fetched), fields required, the '
        'description has its own label', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextJobs = [
        job(id: 'a1b2c3d4e5f6', status: 'completed'),
        job(id: 'b2c3d4e5f6a1', status: 'active'),
      ];
      await openSheet(tester, deps);
      expect(deps.marketplace.jobCalls, 1);
      expect(_textPlain('#QD-A1B2C3D4'), findsOneWidget);
      expect(find.text('Not about an order'), findsOneWidget);
      expect(find.text('What happened?'), findsOneWidget);
      expect(find.text('Contact support & submit complaint tickets'),
          findsNothing);

      await tester.tap(find.byKey(const Key('complaint_send')));
      await tester.pump();
      expect(find.text('Write a subject'), findsOneWidget);
      expect(find.text('Tell us what happened'), findsOneWidget);
      expect(deps.chat.createdContexts, isEmpty);
    });

    testWidgets('sends with the chosen order, then opens its chat',
        (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextJobs = [job(id: 'a1b2c3d4e5f6', status: 'active')];
      deps.chat.nextTickets = [];
      await openSheet(tester, deps);
      await tester.tap(find.byKey(const Key('complaint_order_a1b2c3d4e5f6')));
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('complaint_subject')),
              matching: find.byType(TextField)),
          ' Late order ');
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('complaint_description')),
              matching: find.byType(TextField)),
          'Two hours late');
      await tester.ensureVisible(find.byKey(const Key('complaint_send')));
      await tester.tap(find.byKey(const Key('complaint_send')));
      await tester.pumpAndSettle();
      expect(deps.chat.createdContexts,
          ['Job #a1b2c3d4e5f6 - Late order: Two hours late']);
      expect(find.byType(NewComplaintSheet), findsNothing);
      expect(deps.chat.historyCalls, ['ticket:tkt-new']);
      expect(find.text('Late order'), findsOneWidget); // chat title
    });

    testWidgets('server error stays in the sheet with retry', (tester) async {
      final deps = CustomerTestDeps();
      deps.chat.nextCreateError = Exception('boom');
      await openSheet(tester, deps);
      await tester.tap(find.byKey(const Key('complaint_no_order')));
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('complaint_subject')),
              matching: find.byType(TextField)),
          'App');
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('complaint_description')),
              matching: find.byType(TextField)),
          'Crashes');
      await tester.ensureVisible(find.byKey(const Key('complaint_send')));
      await tester.tap(find.byKey(const Key('complaint_send')));
      await tester.pumpAndSettle();
      expect(deps.chat.createdContexts, ['App: Crashes']);
      expect(find.byKey(const Key('complaint_error')), findsOneWidget);
      expect(find.byType(NewComplaintSheet), findsOneWidget);
      // An outside tap does not close it.
      await tester.tapAt(const Offset(180, 10));
      await tester.pumpAndSettle();
      expect(find.byType(NewComplaintSheet), findsOneWidget);
    });

    testWidgets('orders failing to load still allows sending without one',
        (tester) async {
      final deps = CustomerTestDeps()..marketplace.nextJobsError = 'down';
      await openSheet(tester, deps);
      expect(find.byKey(const Key('complaint_orders_error')), findsOneWidget);
      expect(
          tester
              .widget<QdOptionCard>(find.byKey(const Key('complaint_no_order')))
              .selected,
          isTrue);
    });
  });

  group('ticket chat', () {
    Future<void> openChat(
        WidgetTester tester, CustomerTestDeps deps, SupportTicket t,
        {ChatAttachmentPicker? picker}) async {
      deps.chat.nextTickets = [t];
      await _pumpTickets(tester, deps, picker: picker);
      if (t.isResolved) {
        await tester.tap(find.text('Resolved'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(Key('ticket_${t.id}')));
      await tester.pumpAndSettle();
    }

    testWidgets('resolved ticket: read-only with its resolution',
        (tester) async {
      final deps = CustomerTestDeps();
      await openChat(tester, deps,
          ticket('t1', status: 'resolved', context: 'A: b', note: 'Refunded'));
      expect(find.byKey(const Key('chat_resolved')), findsOneWidget);
      expect(find.text('Resolution: Refunded'), findsOneWidget);
      expect(find.byKey(const Key('chat_input')), findsNothing);
      expect(find.byKey(const Key('chat_read_only')), findsOneWidget);
    });

    testWidgets('a resolution message closes it live', (tester) async {
      final deps = CustomerTestDeps();
      await openChat(tester, deps, ticket('t1', context: 'A: b'));
      expect(find.byKey(const Key('chat_input')), findsOneWidget);
      deps.chat.messages = [
        ChatMessage(
            channel: 'ticket:t1',
            senderId: 'agent',
            senderUsername: 'Sara',
            content: 'We refunded you',
            type: 'ticket_resolution'),
      ];
      deps.chat.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_input')), findsNothing);
      expect(find.text('Resolution: We refunded you'), findsOneWidget);
      expect(find.byKey(const Key('chat_system_line')), findsOneWidget);
    });

    testWidgets('attach: uploads and shows the file', (tester) async {
      final deps = CustomerTestDeps();
      await openChat(tester, deps, ticket('t1', context: 'A: b'),
          picker: (_) async =>
              const ChatAttachment(filename: 'receipt.pdf', bytes: [1, 2, 3]));
      await tester.tap(find.byKey(const Key('chat_attach')));
      await tester.pumpAndSettle();
      expect(deps.chat.uploads, [('t1', 'receipt.pdf', 3)]);
      expect(find.byKey(const Key('chat_attachment')), findsOneWidget);
      expect(find.text('receipt.pdf'), findsOneWidget);
      expect(find.text('3 B'), findsOneWidget);
    });

    for (final (bytes, message) in [
      (<int>[], 'The file is empty.'),
      (List<int>.filled(10 * 1024 * 1024 + 1, 0), 'Files can be up to 10 MB.'),
    ]) {
      testWidgets('attach refuses: $message', (tester) async {
        final deps = CustomerTestDeps();
        await openChat(tester, deps, ticket('t1', context: 'A: b'),
            picker: (_) async =>
                ChatAttachment(filename: 'x.png', bytes: bytes));
        await tester.tap(find.byKey(const Key('chat_attach')));
        await tester.pump();
        expect(find.text(message), findsOneWidget);
        expect(deps.chat.uploads, isEmpty);
      });
    }

    testWidgets('upload failure: notice', (tester) async {
      final deps = CustomerTestDeps()..chat.nextUploadError = Exception('x');
      await openChat(tester, deps, ticket('t1', context: 'A: b'),
          picker: (_) async =>
              const ChatAttachment(filename: 'x.png', bytes: [1]));
      await tester.tap(find.byKey(const Key('chat_attach')));
      await tester.pump();
      expect(find.text("We couldn't send the file."), findsOneWidget);
    });
  });
}
