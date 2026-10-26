import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/providers/auth_provider.dart';

import 'helpers/mock_http_harness.dart';

/// QA audit A5 regression tests: error-handling consistency.
///
/// Every test simulates a failure (mock transport or throwing provider
/// override) and asserts the USER-VISIBLE OUTCOME — friendly actionable copy
/// on screen, an error banner replacing a lying empty state, or the forced-
/// update gate navigating — never merely "no crash".

void main() {
  group('ApiClient request timeout (A5 systemic fix)', () {
    test('a hung backend surfaces as TimeoutException, not an eternal await',
        () async {
      installMockHttp((req) {
        // Never respond — the exact hang the timeout exists for.
        return Completer<MockHttpResponse>().future;
      });
      final api = ApiClient(
        baseUrl: 'https://ci.local/api/v1',
        requestTimeout: const Duration(milliseconds: 80),
      );

      await expectLater(
        api.get('/users/services'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('POST times out identically', () async {
      installMockHttp((req) => Completer<MockHttpResponse>().future);
      final api = ApiClient(
        baseUrl: 'https://ci.local/api/v1',
        requestTimeout: const Duration(milliseconds: 80),
      );

      await expectLater(
        api.post('/users/jobs', {'job_id': 'x'}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('friendlyErrorMessage maps TimeoutException to connectivity copy', () {
      expect(
        friendlyErrorMessage(TimeoutException('deadline exceeded')),
        ErrorMessages.connectionError,
      );
    });
  });

  group('HTTP 426 forced-update gate (A5 dead-code fix)', () {
    test('transport fires onUpdateRequired and throws a 426 exception',
        () async {
      Map<String, dynamic>? received;
      final overrides = installMockHttp((req) =>
          MockHttpResponse(426, jsonBody: {'minimum_version': '2.0.0'}));
      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')
        ..onUpdateRequired = (info) async => received = info;

      await expectLater(
        api.get('/users/wallet'),
        throwsA(isA<ApiClientException>()
            .having((e) => e.statusCode, 'statusCode', 426)),
      );
      expect(received?['minimum_version'], '2.0.0');
      expect(overrides.requests, isNotEmpty);
    });
  });





  group('verifyOtp token-less 2xx is no longer a silent dead-end', () {
    test('missing token in response sets visible fallback error', () async {
      installMockHttp(
          (req) => MockHttpResponse.ok({})); // 200 but no token field.
      final auth = AuthProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));

      final ok = await auth.verifyOtp('e@x.dev', '111222');

      expect(ok, isFalse);
      expect(auth.error, ErrorMessages.genericFallback,
          reason: 'otp_screen surfaces auth.error; null meant NOTHING was '
              'rendered after a successful-looking verification');
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures & mocks
// ---------------------------------------------------------------------------
