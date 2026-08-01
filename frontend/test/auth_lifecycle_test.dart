import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';

void main() {
  group('Auth Lifecycle & Token Refresh Unit Tests', () {
    test('ApiClient initializes with token refresh callbacks null by default',
        () {
      final client = ApiClient();
      expect(client.currentToken, isNull);
      expect(client.onTokenRefreshed, isNull);
      expect(client.onAuthFailed, isNull);
    });

    test('ApiClient setToken updates currentToken', () {
      final client = ApiClient();
      client.setToken('test-token-123');
      expect(client.currentToken, 'test-token-123');
      client.setToken(null);
      expect(client.currentToken, isNull);
    });
  });
}
