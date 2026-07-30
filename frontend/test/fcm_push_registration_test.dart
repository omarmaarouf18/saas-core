import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/push_notification_service.dart';

class MockPushMessagingAdapter implements PushMessagingAdapter {
  String? mockToken = 'mock-fcm-token-abc-123';
  bool deleteTokenCalled = false;
  void Function(String title, String body, Map<String, dynamic> data)?
      onMessageCallback;

  @override
  Future<String?> getToken() async => mockToken;

  @override
  Future<void> deleteToken() async {
    deleteTokenCalled = true;
  }

  @override
  void onForegroundMessage(
      void Function(String title, String body, Map<String, dynamic> data)
          callback) {
    onMessageCallback = callback;
  }
}

class MockApiClient extends ApiClient {
  bool registerCalled = false;
  bool unregisterCalled = false;
  String? lastRegisteredToken;
  String? lastRegisteredPlatform;

  MockApiClient() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> registerDeviceToken({
    required String token,
    String platform = 'android',
    String? action,
  }) async {
    registerCalled = true;
    lastRegisteredToken = token;
    lastRegisteredPlatform = platform;
    return {'message': 'device token registered successfully'};
  }

  @override
  Future<dynamic> unregisterDeviceToken({String? token}) async {
    unregisterCalled = true;
    return {'message': 'device token unregistered successfully'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('FCM Push Notification Registration Tests', () {
    test('ApiClient.registerDeviceToken invokes register endpoint', () async {
      final mockApiClient = MockApiClient();
      final res = await mockApiClient.registerDeviceToken(
        token: 'token-xyz-123',
        platform: 'android',
      );

      expect(res, isA<Map>());
      expect(mockApiClient.registerCalled, isTrue);
      expect(mockApiClient.lastRegisteredToken, equals('token-xyz-123'));
      expect(mockApiClient.lastRegisteredPlatform, equals('android'));
    });

    test(
        'PushNotificationService registers FCM token with ApiClient successfully',
        () async {
      final mockApiClient = MockApiClient();
      final adapter = MockPushMessagingAdapter();
      adapter.mockToken = 'custom-fcm-token-456';

      final service = PushNotificationService(
        apiClient: mockApiClient,
        adapter: adapter,
      );

      final success = await service.registerDeviceToken();
      expect(success, isTrue);
      expect(mockApiClient.registerCalled, isTrue);
      expect(mockApiClient.lastRegisteredToken, equals('custom-fcm-token-456'));
      expect(service.currentToken, equals('custom-fcm-token-456'));
    });

    test('PushNotificationService unregisters FCM token on logout', () async {
      final adapter = MockPushMessagingAdapter();
      final mockApiClient = MockApiClient();

      final service = PushNotificationService(
        apiClient: mockApiClient,
        adapter: adapter,
      );

      final success = await service.unregisterDeviceToken();
      expect(success, isTrue);
      expect(mockApiClient.unregisterCalled, isTrue);
      expect(adapter.deleteTokenCalled, isTrue);
      expect(service.currentToken, isNull);
    });

    test('AuthProvider triggers device token registration and unregistration',
        () async {
      final adapter = MockPushMessagingAdapter();
      final mockApiClient = MockApiClient();
      final pushService = PushNotificationService(
        apiClient: mockApiClient,
        adapter: adapter,
      );

      final authProvider = AuthProvider(
        mockApiClient,
        pushService: pushService,
      );

      expect(authProvider.isAuthenticated, isFalse);

      await authProvider.logout();
      expect(adapter.deleteTokenCalled, isTrue);
      expect(mockApiClient.unregisterCalled, isTrue);
    });
  });
}
