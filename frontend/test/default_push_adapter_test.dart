import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/push_notification_service.dart';

void main() {
  // Regression guard for the FCM stub fix: with Firebase NOT initialized
  // (a build without google-services.json: Firebase.initializeApp() failed
  // at startup, PUSH-FCM), the default adapter must degrade to safe no-ops
  // and must NEVER fabricate a device token.
  group('DefaultPushMessagingAdapter without initialized Firebase', () {
    final adapter = DefaultPushMessagingAdapter();

    test('getToken returns null instead of a fake token', () async {
      final token = await adapter.getToken();
      expect(token, isNull);
    });

    test('deleteToken completes without throwing', () async {
      await expectLater(adapter.deleteToken(), completes);
    });

    test('reports push unavailable (PUSH-FCM)', () async {
      expect(adapter.available, isFalse);
      expect(await adapter.permissionStatus(), PushPermission.unavailable);
      expect(await adapter.requestPermission(), PushPermission.unavailable);
    });

    test('onTokenRefresh is a safe no-op', () {
      expect(() => adapter.onTokenRefresh((_) {}), returnsNormally);
    });
  });
}
