import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/services/push_notification_service.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_push.dart';

/// Records each device-token registration with its locale (PUSH-L10N).
class _Api extends ApiClient {
  _Api() : super(baseUrl: 'https://ci.local/api/v1');

  final List<(String, String?)> calls = [];

  @override
  Future<dynamic> registerDeviceToken({
    required String token,
    String platform = 'android',
    String? action,
    String? locale,
  }) async {
    calls.add((token, locale));
    return {'message': 'ok'};
  }

  @override
  Future<dynamic> unregisterDeviceToken({String? token}) async =>
      {'message': 'ok'};
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  PushNotificationService service(_Api api, FakePushAdapter adapter) =>
      PushNotificationService(
        apiClient: api,
        adapter: adapter,
        promptMemory: MemoryPromptMemory(),
        openSettings: () async => true,
        timeout: const Duration(milliseconds: 200),
      );

  group('token locale (PUSH-L10N)', () {
    test('the app language known at sign-in is sent with the token',
        () async {
      final api = _Api();
      final push = service(api, FakePushAdapter(token: 't1'));
      await push.setLocale('ar');
      expect(api.calls, isEmpty, reason: 'not signed in yet');
      await push.onSignedIn();
      expect(api.calls, [('t1', 'ar')]);
    });

    test('no language known yet: the token goes without one', () async {
      final api = _Api();
      final push = service(api, FakePushAdapter(token: 't1'));
      await push.onSignedIn();
      expect(api.calls, [('t1', null)]);
      // The first frame then reports the language: re-registered with it.
      await push.setLocale('ar');
      expect(api.calls, [('t1', null), ('t1', 'ar')]);
    });

    test('switching the language re-registers the same token', () async {
      final api = _Api();
      final push = service(api, FakePushAdapter(token: 't1'));
      await push.setLocale('ar');
      await push.onSignedIn();
      await push.setLocale('en');
      expect(api.calls, [('t1', 'ar'), ('t1', 'en')]);
      expect(push.locale, 'en');

      await push.setLocale('en'); // unchanged
      await push.setLocale('fr'); // not a server language
      expect(api.calls, hasLength(2));
      expect(push.locale, 'en');
    });

    test('a refreshed token carries the language', () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1');
      final push = service(api, adapter);
      await push.setLocale('en');
      await push.onSignedIn();
      adapter.refreshTo('t2');
      await _settle();
      expect(api.calls, [('t1', 'en'), ('t2', 'en')]);
    });

    test('after sign-out a language switch sends nothing', () async {
      final api = _Api();
      final push = service(api, FakePushAdapter(token: 't1'));
      await push.setLocale('ar');
      await push.onSignedIn();
      await push.unregisterDeviceToken();
      await push.setLocale('en');
      expect(api.calls, [('t1', 'ar')]);
    });

    test('push unavailable in the build: nothing is sent', () async {
      final api = _Api();
      final push = service(api, FakePushAdapter(available: false));
      await push.onSignedIn();
      await push.setLocale('en');
      expect(api.calls, isEmpty);
    });

    test('a switch while the token is being fetched is not lost', () async {
      final api = _Api();
      final adapter = FakePushAdapter(token: 't1')
        ..tokenGate = Completer<String?>();
      final push = service(api, adapter);
      await push.setLocale('ar');
      final signIn = push.onSignedIn();
      await _settle();
      await push.setLocale('en'); // no token yet: remembered only
      expect(api.calls, isEmpty);
      adapter.tokenGate!.complete('t1');
      await signIn;
      expect(api.calls.last, ('t1', 'en'));
    });
  });

  group('PushLocaleSync', () {
    Widget app(PushNotificationService push, Locale locale) =>
        ChangeNotifierProvider<PushNotificationService>.value(
          value: push,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                PushLocaleSync(child: child ?? const SizedBox()),
            home: const SizedBox(),
          ),
        );

    testWidgets('reports the app language and re-registers on a switch',
        (tester) async {
      final api = _Api();
      final push = service(api, FakePushAdapter(token: 't1'));
      await tester.pumpWidget(app(push, const Locale('ar')));
      expect(push.locale, 'ar');

      await tester.runAsync(push.onSignedIn);
      expect(api.calls, [('t1', 'ar')]);

      await tester.pumpWidget(app(push, const Locale('en')));
      await tester.runAsync(_settle);
      expect(push.locale, 'en');
      expect(api.calls, [('t1', 'ar'), ('t1', 'en')]);
    });

    testWidgets('without a push service it only shows the child',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            PushLocaleSync(child: child ?? const SizedBox()),
        home: const Text('home'),
      ));
      expect(find.text('home'), findsOneWidget);
    });
  });
}
