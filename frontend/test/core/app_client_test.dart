import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/app_client.dart';

import '../helpers/mock_http_harness.dart';

/// SPLIT-APPS (ADR-0030): which app a build is, what it accepts, and the
/// X-App-Client header.
void main() {
  tearDown(() => AppClient.debugOverride = null);

  test('tests and a plain flutter run are the customer app', () {
    expect(AppClient.current, AppClient.customer);
    expect(AppClient.resolve(define: ''), AppClient.customer);
  });

  test('APP_CLIENT names the app; the flavor is the fallback', () {
    expect(AppClient.resolve(define: 'console'), AppClient.console);
    expect(AppClient.resolve(define: 'employees', flavor: 'employees'),
        AppClient.employees);
    expect(AppClient.resolve(define: '', flavor: 'console'), AppClient.console);
    expect(AppClient.resolve(define: '', flavor: 'other'), AppClient.customer);
  });

  test('a typo or a define that disagrees with the flavor fails loudly', () {
    expect(() => AppClient.resolve(define: 'consol'), throwsStateError);
    expect(() => AppClient.resolve(define: 'customer', flavor: 'console'),
        throwsStateError);
  });

  test('roles, signup and names per app', () {
    expect(AppClient.customer.allowedRoles, {'user'});
    expect(AppClient.console.allowedRoles, {'owner'});
    expect(AppClient.employees.allowedRoles, {'employee'});

    expect(AppClient.customer.signupRole, 'user');
    expect(AppClient.console.signupRole, 'owner');
    expect(AppClient.employees.signupRole, isNull);
    expect(AppClient.employees.canSignUp, isFalse);

    expect(AppClient.customer.displayName, 'Waddify');
    expect(AppClient.console.displayName, 'Waddify Console');
    expect(AppClient.employees.displayName, 'Waddify Employees');

    expect(AppClient.forRole('user'), AppClient.customer);
    expect(AppClient.forRole('owner'), AppClient.console);
    expect(AppClient.forRole('employee'), AppClient.employees);
    expect(AppClient.forRole('admin'), isNull);
    expect(AppClient.forRole(null), isNull);
  });

  for (final client in AppClient.values) {
    test('every request carries X-App-Client: ${client.name}', () async {
      AppClient.debugOverride = client;
      final overrides = installMockHttp((req) => MockHttpResponse.ok());
      final api =
          ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 'v');

      await api.get('/users/services');
      await api.post('/auth/login', {'email': 'a@b.c'});

      expect(overrides.requests, hasLength(2));
      for (final req in overrides.requests) {
        expect(req.header('X-App-Client'), client.name);
      }
    });
  }
}
