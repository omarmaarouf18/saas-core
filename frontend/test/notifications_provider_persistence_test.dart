import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/notifications_screen.dart';

import 'helpers/mock_http_harness.dart';

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(super.apiClient);

  @override
  String? get token => 'test-token';

  @override
  bool get isAuthenticated => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationModel serialization', () {
    test('fromJson correctly parses is_read true and false', () {
      final readJson = {
        'id': 'n-read',
        'type': 'system',
        'tenant_id': 't1',
        'title': 'Read title',
        'body': 'Read body',
        'timestamp': '2026-08-29T10:00:00.000Z',
        'is_read': true,
      };
      final notifRead = NotificationModel.fromJson(readJson);
      expect(notifRead.isRead, isTrue);

      final unreadJson = {
        'id': 'n-unread',
        'type': 'system',
        'tenant_id': 't1',
        'title': 'Unread title',
        'body': 'Unread body',
        'timestamp': '2026-08-29T10:00:00.000Z',
        'is_read': false,
      };
      final notifUnread = NotificationModel.fromJson(unreadJson);
      expect(notifUnread.isRead, isFalse);

      final defaultJson = {
        'id': 'n-default',
        'type': 'system',
        'tenant_id': 't1',
        'title': 'Default title',
        'body': 'Default body',
        'timestamp': '2026-08-29T10:00:00.000Z',
      };
      final notifDefault = NotificationModel.fromJson(defaultJson);
      expect(notifDefault.isRead, isFalse);
    });

    test('toJson includes is_read field', () {
      final notif = NotificationModel(
        id: 'n-1',
        type: 'jobs',
        tenantId: 't1',
        title: 'Title',
        body: 'Body',
        timestamp: DateTime.parse('2026-08-29T10:00:00.000Z'),
        isRead: true,
      );
      final json = notif.toJson();
      expect(json['is_read'], isTrue);
    });
  });

  group('NotificationsProvider fetchHistory and loadMore', () {
    test('fetchHistory fetches notifications and dedupes against existing items', () async {
      final overrides = installMockHttp((req) {
        expect(req.method, 'GET');
        expect(req.uri.path, endsWith('/notifications/history'));
        expect(req.uri.queryParameters['limit'], '30');

        return MockHttpResponse.ok({
          'notifications': [
            {
              'id': 'notif-1',
              'type': 'system',
              'tenant_id': 't1',
              'title': 'Notif 1',
              'body': 'Body 1',
              'timestamp': '2026-08-29T10:05:00.000Z',
              'is_read': false,
            },
            {
              'id': 'notif-2',
              'type': 'system',
              'tenant_id': 't1',
              'title': 'Notif 2',
              'body': 'Body 2',
              'timestamp': '2026-08-29T10:00:00.000Z',
              'is_read': true,
            },
          ],
          'has_more': false,
        });
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);

      // Pre-seed an item that matches notif-1
      provider.notifications.add(NotificationModel(
        id: 'notif-1',
        type: 'system',
        tenantId: 't1',
        title: 'Notif 1 old',
        body: 'Body 1 old',
        timestamp: DateTime.parse('2026-08-29T10:05:00.000Z'),
        isRead: false,
      ));

      await provider.fetchHistory();

      expect(overrides.requests.length, 1);
      expect(provider.notifications.length, 2);
      expect(provider.notifications[0].id, 'notif-1');
      expect(provider.notifications[1].id, 'notif-2');
      expect(provider.notifications[1].isRead, isTrue);
      expect(provider.hasMore, isFalse);
    });

    test('loadMore queries with before cursor and appends items', () async {
      var callCount = 0;
      installMockHttp((req) {
        callCount++;
        if (callCount == 1) {
          return MockHttpResponse.ok({
            'notifications': [
              {
                'id': 'notif-new',
                'type': 'system',
                'tenant_id': 't1',
                'title': 'New',
                'body': 'Body',
                'timestamp': '2026-08-29T10:10:00.000Z',
                'is_read': false,
              },
            ],
            'has_more': true,
          });
        }

        expect(req.uri.queryParameters['before'], '2026-08-29T10:10:00.000Z');
        return MockHttpResponse.ok({
          'notifications': [
            {
              'id': 'notif-older',
              'type': 'system',
              'tenant_id': 't1',
              'title': 'Older',
              'body': 'Body',
              'timestamp': '2026-08-29T10:00:00.000Z',
              'is_read': true,
            },
          ],
          'has_more': false,
        });
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);

      await provider.fetchHistory();
      expect(provider.notifications.length, 1);
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.notifications.length, 2);
      expect(provider.notifications[0].id, 'notif-new');
      expect(provider.notifications[1].id, 'notif-older');
      expect(provider.hasMore, isFalse);
    });
  });

  group('NotificationsProvider mutations & optimistic rollbacks', () {
    test('markAsRead optimistically updates and rolls back on failure', () async {
      var failApi = false;
      installMockHttp((req) {
        if (req.method == 'POST' && req.uri.path.endsWith('/read')) {
          if (failApi) {
            return MockHttpResponse(500, jsonBody: {'error': 'server error'});
          }
          return MockHttpResponse.ok({'message': 'ok'});
        }
        return MockHttpResponse(404);
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);
      provider.notifications.add(NotificationModel(
        id: 'notif-test-1',
        type: 'system',
        tenantId: 't1',
        title: 'Title',
        body: 'Body',
        timestamp: DateTime.now(),
        isRead: false,
      ));

      // 1. Success case
      await provider.markAsRead('notif-test-1');
      expect(provider.notifications.first.isRead, isTrue);
      expect(provider.error, isNull);

      // 2. Failure case -> rolls back to previous state
      provider.notifications.first.isRead = false;
      failApi = true;
      await provider.markAsRead('notif-test-1');
      expect(provider.notifications.first.isRead, isFalse);
      expect(provider.error, isNotNull);
    });

    test('markAllAsRead optimistically updates and rolls back on failure', () async {
      var failApi = false;
      installMockHttp((req) {
        if (req.method == 'POST' && req.uri.path.endsWith('/read-all')) {
          if (failApi) {
            return MockHttpResponse(500, jsonBody: {'error': 'server error'});
          }
          return MockHttpResponse.ok({'message': 'ok'});
        }
        return MockHttpResponse(404);
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);
      provider.notifications.addAll([
        NotificationModel(
          id: 'n-1',
          type: 'system',
          tenantId: 't1',
          title: '1',
          body: '1',
          timestamp: DateTime.now(),
          isRead: false,
        ),
        NotificationModel(
          id: 'n-2',
          type: 'system',
          tenantId: 't1',
          title: '2',
          body: '2',
          timestamp: DateTime.now(),
          isRead: false,
        ),
      ]);

      // Success
      await provider.markAllAsRead();
      expect(provider.notifications.every((n) => n.isRead), isTrue);

      // Failure
      provider.notifications[0].isRead = false;
      provider.notifications[1].isRead = false;
      failApi = true;
      await provider.markAllAsRead();
      expect(provider.notifications.every((n) => !n.isRead), isTrue);
      expect(provider.error, isNotNull);
    });

    test('dismiss removes item and rolls back on failure', () async {
      var failApi = false;
      installMockHttp((req) {
        if (req.method == 'DELETE' && req.uri.path.endsWith('/n-del')) {
          if (failApi) {
            return MockHttpResponse(500, jsonBody: {'error': 'server error'});
          }
          return MockHttpResponse.ok({'message': 'ok'});
        }
        return MockHttpResponse(404);
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);
      final notif = NotificationModel(
        id: 'n-del',
        type: 'system',
        tenantId: 't1',
        title: 'Title',
        body: 'Body',
        timestamp: DateTime.now(),
      );
      provider.notifications.add(notif);

      // Failure -> item restored
      failApi = true;
      await provider.dismiss('n-del');
      expect(provider.notifications.length, 1);
      expect(provider.error, isNotNull);

      // Success -> item removed
      failApi = false;
      await provider.dismiss('n-del');
      expect(provider.notifications.isEmpty, isTrue);
    });

    test('clearAll clears list and rolls back on failure', () async {
      var failApi = false;
      installMockHttp((req) {
        if (req.method == 'DELETE' && req.uri.path.endsWith('/notifications')) {
          if (failApi) {
            return MockHttpResponse(500, jsonBody: {'error': 'server error'});
          }
          return MockHttpResponse.ok({'message': 'ok'});
        }
        return MockHttpResponse(404);
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);
      provider.notifications.addAll([
        NotificationModel(
          id: 'n-c1',
          type: 'system',
          tenantId: 't1',
          title: '1',
          body: '1',
          timestamp: DateTime.now(),
        ),
      ]);

      // Failure -> list restored
      failApi = true;
      await provider.clearAll();
      expect(provider.notifications.length, 1);
      expect(provider.error, isNotNull);

      // Success -> list cleared
      failApi = false;
      await provider.clearAll();
      expect(provider.notifications.isEmpty, isTrue);
    });
  });

  group('NotificationsScreen pagination widget test', () {
    testWidgets('renders load more button when hasMore is true and triggers loadMore on tap',
        (tester) async {
      var loadMoreCalled = false;
      installMockHttp((req) {
        if (req.method == 'GET' && req.uri.path.endsWith('/notifications/history')) {
          if (req.uri.queryParameters.containsKey('before')) {
            loadMoreCalled = true;
            return MockHttpResponse.ok({'notifications': [], 'has_more': false});
          }
          return MockHttpResponse.ok({
            'notifications': [
              {
                'id': 'notif-w1',
                'type': 'system',
                'tenant_id': 't1',
                'title': 'Widget Notif 1',
                'body': 'Details 1',
                'timestamp': '2026-08-29T10:00:00.000Z',
                'is_read': false,
              },
            ],
            'has_more': true,
          });
        }
        return MockHttpResponse(404);
      });

      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')..setToken('tok');
      final provider = NotificationsProvider(api);
      final auth = _FakeAuthProvider(api);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NotificationsProvider>.value(value: provider),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: NotificationsScreen(),
          ),
        ),
      );

      // Allow post frame callback and initial fetchHistory
      await tester.pumpAndSettle();

      expect(find.text('Widget Notif 1'), findsOneWidget);
      expect(find.byKey(const Key('list_template_load_more_btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('list_template_load_more_btn')));
      await tester.pumpAndSettle();

      expect(loadMoreCalled, isTrue);
    });
  });
}
