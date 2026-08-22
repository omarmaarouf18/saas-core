import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';

import 'helpers/mock_http_harness.dart';

void main() {
  test('sends X-App-Version and Bearer Authorization headers', () async {
    final overrides = installMockHttp((req) => MockHttpResponse.ok());
    final api =
        ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: '7.7.7+9')
          ..setToken('tok-1');

    await api.get('/users/services');

    final req = overrides.requests.single;
    expect(req.header('X-App-Version'), '7.7.7+9');
    expect(req.header('Authorization'), 'Bearer tok-1');
    expect(req.header('Content-Type'), 'application/json');
  });

  test('401 triggers a single refresh and retries with the new token',
      () async {
    var walletAttempts = 0;
    final overrides = installMockHttp((req) {
      if (req.uri.path.endsWith('/auth/refresh')) {
        return MockHttpResponse(200, jsonBody: {'token': 'jwt-new'});
      }
      walletAttempts++;
      if (walletAttempts == 1) {
        return MockHttpResponse(401, jsonBody: {'error': 'expired'});
      }
      expect(req.header('Authorization'), 'Bearer jwt-new');
      return MockHttpResponse(200,
          jsonBody: {'withdrawable_balance': 55.0});
    });
    String? refreshedWith;
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't')
      ..setToken('jwt-old')
      ..onTokenRefreshed = (t) async => refreshedWith = t;

    final res = await api.get('/users/wallet');

    expect(res['withdrawable_balance'], 55.0);
    expect(refreshedWith, 'jwt-new');
    expect(api.currentToken, 'jwt-new');
    expect(
      overrides.requests.where((r) => r.uri.path.endsWith('/auth/refresh')),
      hasLength(1),
    );
  });

  test('two concurrent 401s share ONE refresh (single-flight completer)',
      () async {
    var walletOrLedgerAttempts = 0;
    // Deterministic overlap: hold BOTH original requests open until the test
    // releases them together, guaranteeing their 401s race the refresh path.
    final gate1 = Completer<void>();
    final gate2 = Completer<void>();
    final overrides = installMockHttp((req) {
      if (req.uri.path.endsWith('/auth/refresh')) {
        return MockHttpResponse(200, jsonBody: {'token': 'jwt-shared'});
      }
      walletOrLedgerAttempts++;
      final attempt = walletOrLedgerAttempts;
      final gate = attempt == 1 ? gate1 : (attempt == 2 ? gate2 : null);
      if (gate != null) {
        return gate.future.then(
          (_) => MockHttpResponse(401, jsonBody: {'error': 'expired'}),
        );
      }
      return MockHttpResponse.ok();
    });
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't')
      ..setToken('jwt-old');

    final f1 = api.get('/users/wallet');
    final f2 = api.get('/users/ledger');

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(walletOrLedgerAttempts, 2,
        reason: 'both originals must be in flight and gated');

    gate1.complete();
    gate2.complete();

    await Future.wait([f1, f2]);

    final refreshes = overrides.requests
        .where((r) => r.uri.path.endsWith('/auth/refresh'))
        .length;
    expect(refreshes, 1, reason: 'single-flight must collapse concurrent 401s');
  });

  test('failed refresh fires onAuthFailed once and surfaces the 401',
      () async {
    var authFailures = 0;
    installMockHttp((req) {
      if (req.uri.path.endsWith('/auth/refresh')) {
        return MockHttpResponse(500, jsonBody: {'error': 'redis down'});
      }
      return MockHttpResponse(401, jsonBody: {'error': 'expired'});
    });
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't')
      ..setToken('jwt-old')
      ..onAuthFailed = () async => authFailures++;

    await expectLater(
      api.get('/users/wallet'),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(authFailures, 1);
  });

  test('401 without a stored token fails fast — no refresh attempted',
      () async {
    final overrides = installMockHttp(
        (req) => MockHttpResponse(401, jsonBody: {'error': 'unauthorized'}));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't');

    await expectLater(api.get('/users/wallet'),
        throwsA(isA<ApiClientException>()));

    expect(overrides.requests.where((r) => r.uri.path.endsWith('/refresh')),
        isEmpty);
  });

  test('401 on an auth endpoint never triggers a refresh', () async {
    final overrides = installMockHttp(
        (req) => MockHttpResponse(401, jsonBody: {'error': 'bad password'}));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't')
      ..setToken('jwt-old');

    await expectLater(
      api.post('/auth/login', {'email': 'a', 'password': 'b'}),
      throwsA(isA<ApiClientException>()),
    );
    expect(overrides.requests.where((r) => r.uri.path.endsWith('/refresh')),
        isEmpty);
  });

  test('HTTP 426 invokes onUpdateRequired with the info payload', () async {
    Map<String, dynamic>? receivedInfo;
    installMockHttp((req) => MockHttpResponse(426,
        jsonBody: {
          'message': 'upgrade required',
          'latest_version': '9.9.9',
        }));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: '1')
      ..onUpdateRequired = (info) async { receivedInfo = info; };

    await expectLater(
      api.get('/users/services'),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 426)
          .having((e) => e.message, 'message', 'upgrade required')),
    );
    expect(receivedInfo!['latest_version'], '9.9.9');
  });

  test('transport-level failures wrap into the generic network message',
      () async {
    installMockHttp((req) =>
        throw StateError('socket exploded mid-request'));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't');

    await expectLater(
      api.get('/anything'),
      throwsA(isA<ApiClientException>().having(
          (e) => e.message, 'message',
          contains('Network error: Please check your internet connection.'))),
    );
  });
}
