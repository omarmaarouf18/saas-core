import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';

import 'helpers/mock_http_harness.dart';
import 'helpers/secure_storage_mock.dart';

void main() {
  final storage = SecureStorageMock();

  Future<void> pump([int turns = 8]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ORDERING CONTRACT (same as the other provider suites): install mocks and
  // seed storage BEFORE constructing AuthProvider — its constructor captures
  // the HTTP client and fires async auto-login immediately.
  (AuthProvider, ApiClient) makeAuth({
    required MockHttpHandler handler,
    Map<String, String> seededSession = const {},
  }) {
    storage.reset();
    storage.install();
    storage.store.addAll(seededSession);
    installMockHttp(handler);
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
    return (AuthProvider(api), api);
  }

  const seededSession = {
    'jwt_token': 'jwt-s',
    'user_id': 'u-s',
    'user_email': 's@x.dev',
    'user_username': 'seeded',
    'user_role': 'customer',
    'user_kyc': 'unverified',
  };

  test('auto-login hydrates a session from secure storage', () async {
    late MockHttpOverrides o;
    AuthProvider? auth;
    storage.reset();
    storage.install();
    storage.store.addAll(seededSession);
    o = installMockHttp((req) {
      expect(req.uri.path, endsWith('/auth/user'));
      return MockHttpResponse(200, jsonBody: {
        // Server truth replaces the locally cached display name after hydration.
        'id': 'u-s',
        'email': 's@x.dev',
        'username': 'seeded-server',
        'role': 'customer',
      });
    });
    auth = AuthProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));
    await pump();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.token, 'jwt-s');
    expect(auth.user!.username, 'seeded-server');
    expect(
        o.requests.single.uri.queryParameters['user_token'], 'jwt-s');
  });

  test('no stored session stays unauthenticated without requests', () async {
    final (auth, _) = makeAuth(handler: (req) => MockHttpResponse.ok());
    await pump();

    expect(auth.isAuthenticated, isFalse);
    expect(auth.user, isNull);
  });

  test('login with direct token stores the session and persists it',
      () async {
    final (auth, api) =
        makeAuth(handler: (req) => MockHttpResponse(200, jsonBody: {
              'token': 'jwt-123',
              'user_id': 'u1',
              'username': 'omar',
              'role': 'employee',
              'kyc_status': 'unverified',
            }));
    await pump();

    final otp = await auth.login('e@x.dev', 'pw');

    expect(otp, isNull); // employee login bypasses 2FA
    expect(auth.isAuthenticated, isTrue);
    expect(auth.token, 'jwt-123');
    expect(auth.user!.role, 'employee');
    expect(api.currentToken, 'jwt-123');
    expect(storage.store['jwt_token'], 'jwt-123');
    expect(storage.store['user_id'], 'u1');
    expect(storage.store['user_role'], 'employee');
    expect(auth.isLoading, isFalse);
  });

  test('2FA login returns dev_otp and does NOT authenticate', () async {
    final (auth, _) = makeAuth(handler: (req) => MockHttpResponse(200, jsonBody: {'dev_otp': '424242'}));
    await pump();

    final otp = await auth.login('e@x.dev', 'pw');

    expect(otp, '424242');
    expect(auth.isAuthenticated, isFalse);
    expect(auth.user, isNull);
  });

  test('failed login preserves the backend message and clears loading',
      () async {
    final (auth, _) = makeAuth(handler: (req) =>
        MockHttpResponse(401, jsonBody: {'error': 'invalid credentials'}));
    await pump();

    final otp = await auth.login('e@x.dev', 'wrong');

    expect(otp, isNull);
    // Backend messages on auth endpoints carry no tenant/balance disclosure;
    // passing them verbatim is intentional per the friendly-error policy.
    expect(auth.error, contains('invalid credentials'));
    expect(auth.isLoading, isFalse);
  });

  test('verifyOtp authenticates on a token-bearing response', () async {
    final (auth, _) = makeAuth(handler: (req) {
      expect(req.uri.path, endsWith('/auth/verify-otp'));
      return MockHttpResponse(200, jsonBody: {
        'token': 'jwt-after-otp',
        'user_id': 'u9',
        'email': 'e@x.dev',
        'username': 'nine',
        'role': 'customer',
      });
    });
    await pump();

    final ok = await auth.verifyOtp('e@x.dev', '111222');

    expect(ok, isTrue);
    expect(auth.user!.role, 'customer');
    expect(storage.store['user_role'], 'customer');
  });

  test('signup surfaces dev_otp; duplicate email maps to a friendly error',
      () async {
    var call = 0;
    final (auth, _) = makeAuth(handler: (req) {
      call++;
      if (call == 1) {
        return MockHttpResponse(200, jsonBody: {'dev_otp': '700001'});
      }
      return MockHttpResponse(409, jsonBody: {'error': 'email exists'});
    });
    await pump();

    final otp = await auth.signup('new@x.dev', 'newbie', 'secret1', 'owner');
    expect(otp, '700001');

    final dup = await auth.signup('new@x.dev', 'newbie', 'secret1', 'owner');
    expect(dup, isNull);
    // BEHAVIORAL CONTRACT (discovered during this audit): unlike every other
    // provider (which routes through friendlyErrorMessage), ALL auth flows
    // surface ApiClientException.message VERBATIM because auth endpoints
    // return safe, user-facing strings by contract. Documented in STATUS.md.
    expect(auth.error, 'email exists');
  });

  test('forgotPassword / resendOtp / resetPassword round-trip', () async {
    final (auth, _) = makeAuth(handler: (req) {
      if (req.uri.path.endsWith('/auth/resend-otp')) {
        return MockHttpResponse(200, jsonBody: {'dev_otp': '555000'});
      }
      if (req.uri.path.endsWith('/auth/forgot-password')) {
        return MockHttpResponse(200, jsonBody: {'dev_otp': '321321'});
      }
      expect(req.uri.path, endsWith('/auth/reset-password'));
      expect(jsonDecode(req.body!), {
        'email': 'e@x.dev',
        'otp': '321321',
        'new_password': 'brandNew9',
      });
      return MockHttpResponse(200, jsonBody: {'message': 'ok'});
    });
    await pump();

    expect(await auth.resendOtp('e@x.dev'), '555000');
    expect(await auth.forgotPassword('e@x.dev'), '321321');
    expect(await auth.resetPassword('e@x.dev', '321321', 'brandNew9'), isTrue);
  });

  test('resetPassword failure returns false with the backend reason',
      () async {
    final (auth, _) = makeAuth(
        handler: (req) =>
            MockHttpResponse(401, jsonBody: {'error': 'invalid OTP'}));
    await pump();

    final ok = await auth.resetPassword('e@x.dev', '000000', 'whatever1');

    expect(ok, isFalse);
    expect(auth.error, contains('invalid OTP'));
  });

  test('logout calls the backend, wipes secure storage, clears state',
      () async {
    var call = 0;
    final (auth, api) = makeAuth(handler: (req) {
      call++;
      if (call == 1) {
        return MockHttpResponse(200, jsonBody: {
          'token': 'jwt-live',
          'user_id': 'u2',
          'role': 'owner',
        });
      }
      expect(req.uri.path, endsWith('/auth/logout'));
      return MockHttpResponse.ok();
    });
    await pump();
    await auth.login('o@x.dev', 'pw');
    expect(auth.isAuthenticated, isTrue);

    await auth.logout();

    expect(auth.isAuthenticated, isFalse);
    expect(auth.token, isNull);
    expect(auth.user, isNull);
    expect(api.currentToken, isNull);
    expect(storage.deleteAllCalls, greaterThanOrEqualTo(1));
    expect(call, greaterThanOrEqualTo(2)); // login + logout
  });

  test('forceLogout clears locally without any backend call', () async {
    final (auth, api) =
        makeAuth(handler: (req) => MockHttpResponse.ok(), seededSession: {
          ...seededSession,
        });
    await pump();
    expect(auth.isAuthenticated, isTrue);

    await auth.forceLogout();

    expect(auth.isAuthenticated, isFalse);
    expect(api.currentToken, isNull);
  });

  test('updateOwnProfile applies the returned user envelope', () async {
    var call = 0;
    final (auth, _) = makeAuth(handler: (req) {
      call++;
      if (call == 1) {
        return MockHttpResponse(200,
            jsonBody: {'id': 'u-s', 'email': 's@x.dev', 'role': 'customer'});
      }
      expect(req.method, 'PATCH');
      expect(jsonDecode(req.body!), {
        'username': 'renamed',
        'phone': '+201000000000',
        'frequent_addresses': ['Home', 'Work'],
      });
      return MockHttpResponse(200, jsonBody: {
        'user': {
          'id': 'u-s',
          'email': 's@x.dev',
          'username': 'renamed',
          'phone': '+201000000000',
          'role': 'customer',
          'frequent_addresses': ['Home', 'Work'],
        },
      });
    }, seededSession: {...seededSession});
    await pump(); // auto-login consumes call 1

    final ok = await auth.updateOwnProfile(
      username: 'renamed',
      phone: '+201000000000',
      frequentAddresses: const ['Home', 'Work'],
    );

    expect(ok, isTrue);
    expect(auth.user!.username, 'renamed');
    expect(auth.user!.frequentAddresses, ['Home', 'Work']);
    expect(storage.store['user_username'], 'renamed');
  });

  test('uploadDocument rejects unauthenticated callers before any request',
      () async {
    final (auth, api) = makeAuth(handler: (req) => MockHttpResponse.ok());
    await pump();

    await expectLater(
      auth.uploadDocument(docType: 'id_front', fileBytes: [1], filename: 'a'),
      throwsA(isA<ApiClientException>()),
    );
  });

  test('uploadDocument rejects customer-role accounts', () async {
    final (auth, api) = makeAuth(handler: (req) => MockHttpResponse.ok(),
        seededSession: {...seededSession});
    await pump();

    await expectLater(
      auth.uploadDocument(docType: 'id_front', fileBytes: [1], filename: 'a'),
      throwsA(isA<ApiClientException>()),
    );
  });
}
