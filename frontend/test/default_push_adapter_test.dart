import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/push_notification_service.dart';

void main() {
  // Regression guard for the FCM stub fix: with Firebase NOT initialized
  // (the state of every current build — there is no Firebase.initializeApp()
  // call and no platform config files), the default adapter must degrade to
  // safe no-ops and must NEVER fabricate a device token.
  group('DefaultPushMessagingAdapter without initialized Firebase', () {
    final adapter = DefaultPushMessagingAdapter();

    test('getToken returns null instead of a fake token', () async {
      final token = await adapter.getToken();
      expect(token, isNull);
    });

    test('deleteToken completes without throwing', () async {
      await expectLater(adapter.deleteToken(), completes);
    });

    test('onForegroundMessage is a safe no-op', () {
      expect(
        () => adapter.onForegroundMessage((title, body, data) {}),
        returnsNormally,
      );
    });
  });
}
