import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/chat/chat_page.dart';
import 'package:frontend/models/chat_message.dart';

import '../customer_harness.dart';

ChatMessage _msg(String id, String sender, String text, {String name = ''}) =>
    ChatMessage(
      id: id,
      channel: 'job:j1',
      senderId: sender,
      senderUsername: name,
      content: text,
      type: 'message',
      createdAt: fixedNow,
    );

Future<void> _pump(WidgetTester tester, CustomerTestDeps deps,
    {Locale locale = en}) async {
  usePhone(tester);
  await tester.pumpWidget(customerApp(
    deps,
    const CustomerChatPage(
        channel: 'job:j1', title: 'Chat with the courier', subtitle: '#QD-J1'),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads history, then connects; shows messages and who sent them',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.chat.nextHistory = [
      _msg('1', 'emp-1', 'On my way', name: 'Karim'),
      _msg('2', 'user-1', 'Thanks'),
      _msg('3', 'abcdef123', 'Hello'),
    ];
    await _pump(tester, deps);

    expect(deps.chat.historyCalls, ['job:j1']);
    expect(deps.chat.connectCalls, ['job:j1']);
    expect(find.text('On my way'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('User abcdef'), findsOneWidget);
    expect(find.text('#QD-J1 · Connected'), findsOneWidget);
  });

  testWidgets('loader while history loads, then the empty state',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.chat.historyGate = Completer<void>();
    usePhone(tester);
    await tester.pumpWidget(customerApp(
        deps, const CustomerChatPage(channel: 'job:j1', title: 'Chat')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('chat_loading')), findsOneWidget);
    expect(find.byKey(const Key('chat_empty')), findsNothing);

    deps.chat.historyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat_empty')), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('access denied: banner, no composer, no websocket',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.chat.nextHistoryDenied = true;
    await _pump(tester, deps);

    expect(find.byKey(const Key('chat_denied')), findsOneWidget);
    expect(find.byKey(const Key('chat_input')), findsNothing);
    expect(deps.chat.connectCalls, isEmpty);

    // Retry asks again.
    deps.chat.nextHistoryDenied = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(deps.chat.historyCalls, hasLength(2));
    expect(deps.chat.connectCalls, ['job:j1']);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
  });

  testWidgets('history error: banner with retry, composer stays',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.chat.nextHistoryError = 'Network error';
    await _pump(tester, deps);
    expect(find.byKey(const Key('chat_error')), findsOneWidget);
    expect(find.text('Network error'), findsOneWidget);
    expect(find.byKey(const Key('chat_input')), findsOneWidget);
  });

  testWidgets('send trims, ignores empty text, guards double taps',
      (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);

    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    expect(deps.chat.sent, isEmpty);

    deps.chat.sendGate = Completer<void>();
    await tester.enterText(find.byKey(const Key('chat_input')), '  Gate 3  ');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    expect(deps.chat.sent, ['Gate 3']);

    deps.chat.sendGate!.complete();
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(const Key('chat_input')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('a failed send keeps the text and offers retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.chat.nextSendError = Exception('WebSocket is not connected');
    await _pump(tester, deps);
    await tester.enterText(find.byKey(const Key('chat_input')), 'Hi');
    await tester.tap(find.byKey(const Key('chat_send')));
    await tester.pump();
    expect(
        find.textContaining("We couldn't send the message."), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('chat_input')));
    expect(field.controller!.text, 'Hi');
  });

  testWidgets('closing the page disconnects the chat socket', (tester) async {
    final deps = CustomerTestDeps();
    await _pump(tester, deps);
    expect(deps.chat.disconnects, 0);
    await tester.pumpWidget(customerApp(deps, const SizedBox()));
    await tester.pump();
    expect(deps.chat.disconnects, 1);
  });

  for (final locale in bothLocales) {
    testWidgets('renders without overflow [${locale.languageCode}]',
        (tester) async {
      final deps = CustomerTestDeps();
      deps.chat.nextHistory = [
        _msg('1', 'emp-1', 'A long message ' * 12, name: 'Karim'),
        _msg('2', 'user-1', 'OK'),
      ];
      await _pump(tester, deps, locale: locale);
      expect(tester.takeException(), isNull);
    });
  }
}
