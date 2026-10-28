import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/push_notification_service.dart';
import 'package:frontend/services/push_setup.dart';

import '../helpers/fake_push.dart';

/// Records device-token calls; answers /auth/login with a session.
class _Api extends ApiClient {
  _Api() : super(baseUrl: 'https://ci.local/api/v1');

  final List<String> registered = [];
  final List<String?> unregistered = [];
  bool failRegister = false;

  @override
  Future<dynamic> registerDeviceToken({
    required String token,
    String platform = 'android',
    String? action,
  }) async {
    if (failRegister) throw ApiClientException('down', statusCode: 503);
    registered.add(token);
    return {'message': 'ok'};
  }

  @override
  Future<dynamic> unregisterDeviceToken({String? token}) async {
    unregistered.add(token);
    return {'message': 'ok'};
  }

  @override
  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    if (path == '/auth/login') {
      return {
        'token': 'jwt',
        'user_id': 'u1',
        'username': 'mona',
        'role': 'user',
      };
    }
    return <String, dynamic>{};
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  PushNotificationService service(_Api api, FakePushAdapter adapter,
          {MemoryPromptMemory? memory}) =>
      PushNotificationService(
        apiClient: api,
        adapter: adapter,
        promptMemory: memory ?? MemoryPromptMemory(),
        openSettings: () async => true,
        timeout: const Duration(milliseconds: 200),
      );

  group('token register / refresh / unregister', () {
    test('sign-in registers the token and follows refreshes', () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1');
      final push = service(api, adapter);
      await push.onSignedIn();
      expect(api.registered, ['t1']);
      expect(adapter.listensForRefresh, isTrue);

      adapter.refreshTo('t2');
      await _settle();
      expect(api.registered, ['t1', 't2']);
      expect(push.currentToken, 't2');

      // The same token again is not re-sent.
      adapter.refreshTo('t2');
      await _settle();
      expect(api.registered, ['t1', 't2']);
    });

    test('sign-out unregisters, deletes the token, ignores later refreshes',
        () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1');
      final push = service(api, adapter);
      await push.onSignedIn();
      expect(await push.unregisterDeviceToken(), isTrue);
      expect(api.unregistered, ['t1']);
      expect(adapter.deleteTokenCalls, 1);
      expect(push.currentToken, isNull);

      adapter.refreshTo('t3');
      await _settle();
      expect(api.registered, ['t1'], reason: 'no push after logout');
    });

    test('a second sign-in does not add a second refresh listener', () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1');
      final push = service(api, adapter);
      await push.onSignedIn();
      await push.unregisterDeviceToken();
      await push.onSignedIn();
      adapter.refreshTo('t9');
      await _settle();
      expect(api.registered.where((t) => t == 't9'), hasLength(1));
    });

    test('unavailable (no Firebase config): nothing is called', () async {
      final api = _Api();
      final adapter = FakePushAdapter(available: false);
      final push = service(api, adapter);
      await push.onSignedIn();
      expect(adapter.getTokenCalls, 0);
      expect(api.registered, isEmpty);
      expect(push.permission, PushPermission.unavailable);
      expect(push.shouldOfferPrompt, isFalse);
    });

    test('a failing register never throws', () async {
      final api = _Api()..failRegister = true;
      final push = service(api, FakePushAdapter());
      await expectLater(push.onSignedIn(), completes);
      expect(await push.registerDeviceToken(), isFalse);
    });

    test('a hanging getToken times out', () async {
      final adapter = FakePushAdapter()..tokenGate = Completer<String?>();
      final push = service(_Api(), adapter);
      expect(await push.registerDeviceToken(), isFalse);
    });
  });

  group('login never waits for push', () {
    test('login completes while getToken hangs; registers when it answers',
        () async {
      final api = _Api();
      final gate = Completer<String?>();
      final adapter = FakePushAdapter()..tokenGate = gate;
      final push = PushNotificationService(
        apiClient: api,
        adapter: adapter,
        promptMemory: MemoryPromptMemory(),
        timeout: const Duration(seconds: 30),
      );
      final auth = AuthProvider(api, pushService: push);
      await _settle();

      await auth.login('m@x.dev', 'pw').timeout(const Duration(seconds: 2));
      expect(auth.isAuthenticated, isTrue);
      expect(api.registered, isEmpty);

      gate.complete('late-token');
      await _settle();
      expect(api.registered, ['late-token']);
    });
  });

  group('permission flow', () {
    test('not asked yet → prompt offered; grant registers again', () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1');
      final memory = MemoryPromptMemory();
      final push = service(api, adapter, memory: memory);
      await push.onSignedIn();
      expect(push.permission, PushPermission.notDetermined);
      expect(push.shouldOfferPrompt, isTrue);

      expect(await push.requestPermission(), PushPermission.granted);
      expect(push.permission, PushPermission.granted);
      expect(memory.isAnswered, isTrue);
      expect(push.shouldOfferPrompt, isFalse);
      expect(api.registered, ['t1', 't1']);
    });

    test('denied: not offered again, no register', () async {
      final api = _Api();
      final adapter = FakePushAdapter(answer: PushPermission.blocked);
      final push = service(api, adapter);
      await push.onSignedIn();
      expect(await push.requestPermission(), PushPermission.blocked);
      expect(push.shouldOfferPrompt, isFalse);
      expect(api.registered, hasLength(1));
    });

    test('"Not now" is remembered; a later sign-in does not offer it',
        () async {
      final memory = MemoryPromptMemory();
      final push = service(_Api(), FakePushAdapter(), memory: memory);
      await push.onSignedIn();
      await push.markPromptAnswered();
      expect(push.shouldOfferPrompt, isFalse);

      final again = service(_Api(), FakePushAdapter(), memory: memory);
      await again.onSignedIn();
      expect(again.shouldOfferPrompt, isFalse);
      expect(again.permission, PushPermission.notDetermined);
    });

    test('already granted (Android 12 and older) → never offered', () async {
      final push = service(
          _Api(), FakePushAdapter(status: PushPermission.granted));
      await push.onSignedIn();
      expect(push.shouldOfferPrompt, isFalse);
    });

    test('refreshPermission picks up a change made in the phone settings',
        () async {
      final adapter = FakePushAdapter(status: PushPermission.blocked);
      final push = service(_Api(), adapter);
      await push.onSignedIn();
      var notified = 0;
      push.addListener(() => notified++);
      adapter.status = PushPermission.granted;
      expect(await push.refreshPermission(), PushPermission.granted);
      expect(notified, 1);
    });
  });

  group('initPushFirebase', () {
    test('no config → push off, no throw', () async {
      final ok = await initPushFirebase(
        supported: true,
        initializeApp: () async =>
            throw Exception('[core/not-initialized] no google-services.json'),
      );
      expect(ok, isFalse);
    });

    test('a hanging init times out → push off', () async {
      final ok = await initPushFirebase(
        supported: true,
        initializeApp: () => Completer<Object?>().future,
        timeout: const Duration(milliseconds: 50),
      );
      expect(ok, isFalse);
    });

    test('unsupported platform → push off, init not called', () async {
      var called = false;
      final ok = await initPushFirebase(
        supported: false,
        initializeApp: () async => called = true,
      );
      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('configured → push on, background handler registered', () async {
      var registered = 0;
      expect(
          await initPushFirebase(
              supported: true,
              initializeApp: () async => null,
              registerBackgroundHandler: () => registered++),
          isTrue);
      expect(registered, 1);
    });

    test('the background handler is a top-level no-op', () async {
      await expectLater(
          pushBackgroundHandler(const RemoteMessage(data: {'type': 'x'})),
          completes);
    });
  });
}
