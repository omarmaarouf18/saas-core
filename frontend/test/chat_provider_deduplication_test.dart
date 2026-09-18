import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/providers/chat_provider.dart';

void main() {
  late ApiClient apiClient;
  late ChatProvider chatProvider;

  setUp(() {
    apiClient = ApiClient(baseUrl: 'https://example.com/api/v1');
    chatProvider = ChatProvider(apiClient);
  });

  group('ChatMessage model', () {
    test('parses id, created_at, and serializes correctly', () {
      final jsonMap = {
        'id': 'msg-test-123',
        'channel': 'job:456',
        'sender_id': 'user-1',
        'sender_username': 'Alice',
        'content': 'Hello world',
        'type': 'message',
        'created_at': '2026-09-18T10:00:00.000Z',
      };

      final msg = ChatMessage.fromJson(jsonMap);
      expect(msg.id, 'msg-test-123');
      expect(msg.channel, 'job:456');
      expect(msg.senderId, 'user-1');
      expect(msg.senderUsername, 'Alice');
      expect(msg.content, 'Hello world');
      expect(msg.type, 'message');
      expect(msg.createdAt, DateTime.parse('2026-09-18T10:00:00.000Z'));

      final serialized = msg.toJson();
      expect(serialized['id'], 'msg-test-123');
      expect(serialized['created_at'], '2026-09-18T10:00:00.000Z');
    });

    test('falls back to timestamp field if created_at is absent', () {
      final jsonMap = {
        'id': 'msg-456',
        'channel': 'job:456',
        'sender_id': 'user-2',
        'sender_username': 'Bob',
        'content': 'Hi',
        'type': 'message',
        'timestamp': '2026-09-18T10:05:00.000Z',
      };

      final msg = ChatMessage.fromJson(jsonMap);
      expect(msg.id, 'msg-456');
      expect(msg.createdAt, DateTime.parse('2026-09-18T10:05:00.000Z'));
    });
  });

  group('ChatProvider deduplication', () {
    test('does NOT drop identical text sent with distinct message IDs', () {
      // Prior bug: sending "Where are you?" twice would drop the 2nd message
      // because deduplication was based strictly on (senderId, content, type).
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'id': 'msg-001',
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'Where are you?',
        'type': 'message',
        'created_at': '2026-09-18T10:00:00.000Z',
      }));

      expect(chatProvider.messages.length, 1);
      expect(chatProvider.messages.first.content, 'Where are you?');

      // Second identical message sent moments later with a new unique message ID
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'id': 'msg-002',
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'Where are you?',
        'type': 'message',
        'created_at': '2026-09-18T10:01:00.000Z',
      }));

      expect(chatProvider.messages.length, 2,
          reason:
              'consecutive identical text with distinct IDs must both be preserved');
      expect(chatProvider.messages[0].id, 'msg-001');
      expect(chatProvider.messages[1].id, 'msg-002');
      expect(chatProvider.messages[0].content, 'Where are you?');
      expect(chatProvider.messages[1].content, 'Where are you?');
    });

    test('deduplicates replayed messages with the same message ID', () {
      // Pre-seed message from history
      chatProvider.setMessagesForTesting([
        ChatMessage(
          id: 'msg-hist-99',
          channel: 'job:100',
          senderId: 'courier-1',
          senderUsername: 'Courier',
          content: 'Arrived at pickup location',
          type: 'message',
          createdAt: DateTime.parse('2026-09-18T09:50:00.000Z'),
        ),
      ]);

      expect(chatProvider.messages.length, 1);

      // Replay the exact same message via WebSocket broadcast
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'id': 'msg-hist-99',
        'channel': 'job:100',
        'sender_id': 'courier-1',
        'sender_username': 'Courier',
        'content': 'Arrived at pickup location',
        'type': 'message',
        'created_at': '2026-09-18T09:50:00.000Z',
      }));

      expect(chatProvider.messages.length, 1,
          reason: 'replayed message with identical ID must be deduplicated');
    });

    test('does NOT drop identical text with different timestamps (> 2s)', () {
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'ok',
        'type': 'message',
        'created_at': '2026-09-18T10:00:00.000Z',
      }));

      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'ok',
        'type': 'message',
        'created_at': '2026-09-18T10:00:05.000Z',
      }));

      expect(chatProvider.messages.length, 2,
          reason: 'identical text separated by 5s must both be preserved');
    });

    test('deduplicates messages within 2s window when IDs are missing', () {
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'rapid double tap',
        'type': 'message',
        'created_at': '2026-09-18T10:00:00.000Z',
      }));

      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'rapid double tap',
        'type': 'message',
        'created_at':
            '2026-09-18T10:00:01.000Z', // 1s apart, same sender/content
      }));

      expect(chatProvider.messages.length, 1,
          reason:
              'unidentified message within 2s window from same sender with identical content is treated as duplicate');
    });

    test(
        'does NOT drop consecutive identical messages when neither has ID or timestamp',
        () {
      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'yes',
        'type': 'message',
      }));

      chatProvider.handleIncomingDataForTesting(jsonEncode({
        'channel': 'job:100',
        'sender_id': 'cust-1',
        'sender_username': 'Customer',
        'content': 'yes',
        'type': 'message',
      }));

      expect(chatProvider.messages.length, 2,
          reason:
              'identical content without ID or timestamp must not be aggressively dropped');
    });
  });
}
