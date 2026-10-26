import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/owner_provider.dart';

/// SEC-07b backend contracts:
///  * POST /auth/employee/toggle fails closed with 503
///    (service_unavailable) when session revocation fails — the employee is
///    NOT frozen and the UI must say "temporarily unavailable, try again"
///    without mutating state.
///  * GET /auth/employees returns 500 on a database error (no more empty
///    200 []) — the screen must show the error banner with retry, never the
///    "no employees" empty state.
void main() {
  test('OwnerProvider.toggleEmployee propagates the 503 and records the error',
      () async {
    final api = _FailingToggleApi();
    final provider = OwnerProvider(api);

    await expectLater(
      provider.toggleEmployee(
        employeeEmail: 'courier@company.com',
        ownerEmail: 'owner@example.com',
        ownerPassword: 'owner-pass-9',
        setActive: false,
      ),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'statusCode', 503)),
    );
    expect(provider.error, isNotNull);
  });
}

class _FailingToggleApi extends ApiClient {
  _FailingToggleApi() : super(baseUrl: 'http://localhost:3002');

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/employee/toggle') {
      // Realistic backend 503 body (handlerutil.SafeError): the message the
      // user sees and the machine code lifted to ApiClientException.
      throw ApiClientException(
        'failed to freeze employee account, please retry',
        statusCode: 503,
        errorCode: 'service_unavailable',
      );
    }
    return {};
  }
}
