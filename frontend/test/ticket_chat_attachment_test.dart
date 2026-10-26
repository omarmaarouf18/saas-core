import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;

  MockAuthProviderForTest(
    super.apiClient, {
    this.mockUser,
    this.mockToken = 'test-token',
  });

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;
}

class MockChatProviderWithAttachments extends ChatProvider {
  List<ChatMessage> mockMessages;
  String? lastSubscribedChannel;
  bool uploadTicketAttachmentCalled = false;
  String? lastUploadedTicketId;
  String? lastUploadedFilename;
  List<int>? lastUploadedBytes;

  MockChatProviderWithAttachments(
    super.apiClient, {
    this.mockMessages = const [],
  }) : super();

  @override
  List<ChatMessage> get messages => mockMessages;

  @override
  bool get isConnected => true;

  @override
  Future<void> fetchChannelHistory(String channel, String token) async {
    lastSubscribedChannel = channel;
  }

  @override
  void connectAndSubscribeChannel(String channel, String token) {
    lastSubscribedChannel = channel;
  }

  @override
  Future<ChatMessage?> uploadTicketAttachment({
    required String ticketId,
    required List<int> fileBytes,
    required String filename,
    String? content,
  }) async {
    uploadTicketAttachmentCalled = true;
    lastUploadedTicketId = ticketId;
    lastUploadedFilename = filename;
    lastUploadedBytes = fileBytes;

    final msg = ChatMessage(
      id: 'msg-attach-1',
      channel: 'ticket:$ticketId',
      senderId: 'cust-101',
      senderUsername: 'AliceCustomer',
      content: content ?? filename,
      type: 'attachment',
      attachmentKey: 'tickets/$ticketId/test.jpg',
      attachmentUrl: 'https://example.com/attachments/test.jpg',
      attachmentName: filename,
      attachmentType: 'image/jpeg',
      attachmentSize: fileBytes.length,
      createdAt: DateTime.now(),
    );
    mockMessages = [...mockMessages, msg];
    notifyListeners();
    return msg;
  }

  @override
  void disconnect() {}
}

class MockNotificationsProviderForTest extends NotificationsProvider {
  MockNotificationsProviderForTest(super.apiClient) : super();

  @override
  List<NotificationModel> get notifications => [];

  @override
  bool get isConnected => true;

  @override
  Future<void> fetchHistory({bool refresh = false, int limit = 30}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMessage Model Attachment Serialization', () {
    test('serializes and deserializes attachment fields correctly', () {
      final json = {
        'id': 'msg-123',
        'channel': 'ticket:t-1',
        'sender_id': 'u-1',
        'sender_username': 'Alice',
        'content': 'receipt.pdf',
        'type': 'attachment',
        'attachment_key': 'tickets/t-1/receipt.pdf',
        'attachment_url':
            'https://storage.local/chat/attachments/view?token=abc',
        'attachment_name': 'receipt.pdf',
        'attachment_type': 'application/pdf',
        'attachment_size': 2048576,
        'created_at': '2026-09-22T10:00:00.000Z',
      };

      final msg = ChatMessage.fromJson(json);
      expect(msg.id, equals('msg-123'));
      expect(msg.channel, equals('ticket:t-1'));
      expect(msg.attachmentKey, equals('tickets/t-1/receipt.pdf'));
      expect(msg.attachmentUrl,
          equals('https://storage.local/chat/attachments/view?token=abc'));
      expect(msg.attachmentName, equals('receipt.pdf'));
      expect(msg.attachmentType, equals('application/pdf'));
      expect(msg.attachmentSize, equals(2048576));

      final serialized = msg.toJson();
      expect(serialized['attachment_key'], equals('tickets/t-1/receipt.pdf'));
      expect(serialized['attachment_url'],
          equals('https://storage.local/chat/attachments/view?token=abc'));
      expect(serialized['attachment_name'], equals('receipt.pdf'));
      expect(serialized['attachment_type'], equals('application/pdf'));
      expect(serialized['attachment_size'], equals(2048576));
    });
  });

  group('ApiClient postMultipart', () {
    test('removes Content-Type header so multipart boundary is preserved',
        () async {
      http.BaseRequest? capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'id': 'uploaded-1', 'status': 'ok'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('jwt-token-123');

      final res = await apiClient.postMultipart(
        '/chat/tickets/t-100/attachment',
        fieldName: 'file',
        fileBytes: [1, 2, 3, 4],
        filename: 'test.png',
        fields: {'content': 'My receipt'},
      );

      expect(res, isA<Map<String, dynamic>>());
      expect(res['id'], equals('uploaded-1'));
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['content-type'],
          startsWith('multipart/form-data; boundary='));
      expect(capturedRequest!.headers['Authorization'],
          equals('Bearer jwt-token-123'));
    });
  });

  group('ChatProvider uploadTicketAttachment', () {
    test('uploads attachment and appends to messages', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'msg-999',
            'channel': 'ticket:t-200',
            'sender_id': 'u-1',
            'sender_username': 'Alice',
            'content': 'photo.jpg',
            'type': 'attachment',
            'attachment_key': 'tickets/t-200/photo.jpg',
            'attachment_url':
                'https://storage.local/chat/attachments/view?token=xyz',
            'attachment_name': 'photo.jpg',
            'attachment_type': 'image/jpeg',
            'attachment_size': 4096,
            'created_at': DateTime.now().toIso8601String(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final provider = ChatProvider(apiClient);

      final msg = await provider.uploadTicketAttachment(
        ticketId: 't-200',
        fileBytes: [10, 20, 30],
        filename: 'photo.jpg',
      );

      expect(msg, isNotNull);
      expect(msg!.id, equals('msg-999'));
      expect(msg.attachmentName, equals('photo.jpg'));
      expect(provider.messages.length, equals(1));
      expect(provider.messages.first.id, equals('msg-999'));
    });
  });

}
