import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/auth_provider.dart';

/// FE-AUTH-ACCOUNT provider change: the machine code and server reason of
/// the last failed auth call are kept next to [AuthProvider.error].
class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:3002');

  Object? nextError;

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
    return <String, dynamic>{'status': 'ok'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('weak_password on signup keeps code and reason; banner text unchanged',
      () async {
    final api = _Api();
    final auth = AuthProvider(api);
    api.nextError = ApiClientException('password is too common',
        statusCode: 400, errorCode: 'weak_password');
    await auth.signup('a@b.co', 'Mona', 'password123', 'user');
    expect(auth.lastErrorCode, 'weak_password');
    expect(auth.lastErrorReason, 'password is too common');
    expect(
        auth.error, 'This password is too common — pick a less guessable one.');
  });

  test('a new call clears them; clearError clears them', () async {
    final api = _Api();
    final auth = AuthProvider(api);
    api.nextError = ApiClientException('password is too common',
        statusCode: 400, errorCode: 'weak_password');
    await auth.resetPassword('a@b.co', 'tok', 'password123');
    expect(auth.lastErrorCode, 'weak_password');

    await auth.resetPassword('a@b.co', 'tok', 'better-password-9');
    expect(auth.error, isNull);
    expect(auth.lastErrorCode, isNull);
    expect(auth.lastErrorReason, isNull);

    api.nextError = ApiClientException('nope', statusCode: 401);
    await auth.login('a@b.co', 'x');
    expect(auth.lastErrorCode, isNull);
    expect(auth.lastErrorReason, 'nope');
    auth.clearError();
    expect(auth.lastErrorReason, isNull);
  });

  test('non-API failures carry no code or reason', () async {
    final api = _Api();
    final auth = AuthProvider(api);
    api.nextError = StateError('offline');
    await auth.forgotPassword('a@b.co');
    expect(auth.error, isNotNull);
    expect(auth.lastErrorCode, isNull);
    expect(auth.lastErrorReason, isNull);
  });
}
