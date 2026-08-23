import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';

import 'helpers/mock_http_harness.dart';

/// IMPORTANT ORDERING CONTRACT: ApiClient captures its underlying HttpClient
/// at construction time (via HttpOverrides.global). Every test must therefore
/// installMockHttp(...) FIRST and only then construct its own provider.
(EmployeeJobsProvider, MockHttpOverrides) _makeProvider(
  MockHttpHandler handler, {
  String? token,
}) {
  final overrides = installMockHttp(handler);
  final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
  if (token != null) api.setToken(token);
  return (EmployeeJobsProvider(api), overrides);
}

void main() {
  test('fetchAssignedJobs parses a plain list response', () async {
    final (provider, overrides) = _makeProvider((req) {
      expect(req.uri.path, endsWith('/users/jobs/get'));
      return MockHttpResponse(200, jsonBody: [
        {'id': 'job-1', 'status': 'active', 'payment_method': 'cod'},
      ]);
    });

    await provider.fetchAssignedJobs('emp-token');

    expect(provider.jobs.length, 1);
    expect(provider.jobs.first.id, 'job-1');
    expect(provider.jobs.first.status, 'active');
    expect(provider.error, isNull);
    final req = overrides.requests.single;
    expect(req.uri.queryParameters['requester_id'], 'emp-token');
    // IDOR-safe contract: token travels as requester_id, never as user_id.
    expect(req.uri.queryParameters.containsKey('user_id'), isFalse);
  });

  test('fetchAssignedJobs parses the {"jobs": [...]} wrapper variant',
      () async {
    final (provider, _) = _makeProvider(
        (req) => MockHttpResponse(200, jsonBody: {'jobs': [
              {'id': 'job-w'}
            ]}));

    await provider.fetchAssignedJobs('t');

    expect(provider.jobs.single.id, 'job-w');
  });

  test('fetchAssignedJobs falls back to a single-job map payload', () async {
    final (provider, _) = _makeProvider(
        (req) => MockHttpResponse(200, jsonBody: {'id': 'solo'}));

    await provider.fetchAssignedJobs('t');

    expect(provider.jobs.single.id, 'solo');
  });

  test('fetchAssignedJobs surfaces friendly errors and clears loading',
      () async {
    final (provider, _) = _makeProvider(
        (req) => MockHttpResponse(429, jsonBody: {'error': 'rate limited'}));

    await provider.fetchAssignedJobs('t');

    expect(provider.isLoading, isFalse);
    expect(provider.error,
        friendlyErrorMessage(ApiClientException('x', statusCode: 429)));
  });

  test('completeJob posts cash_collected=true for COD jobs and completes locally',
      () async {
    var seenGet = false;
    final (provider, overrides) = _makeProvider((req) {
      if (req.uri.path.endsWith('/users/jobs/get')) {
        seenGet = true;
        return MockHttpResponse(200, jsonBody: [
          {'id': 'job-cod', 'status': 'active', 'payment_method': 'cod'}
        ]);
      }
      return MockHttpResponse.ok();
    }, token: 'emp-jwt-token');

    await provider.fetchAssignedJobs('emp-jwt-token');
    expect(seenGet, isTrue);

    await provider.completeJob('job-cod', cashCollected: true);

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/complete'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'job-cod',
      'cash_collected': true,
      'requester_id': 'emp-jwt-token',
    });
    expect(provider.jobs.first.status, 'completed');
    expect(provider.isLoading, isFalse);
  });

  test('completeJob posts cash_collected=false when cash was not collected',
      () async {
    final (provider, overrides) = _makeProvider((req) {
      if (req.uri.path.endsWith('/users/jobs/get')) {
        return MockHttpResponse(200,
            jsonBody: [{'id': 'j', 'status': 'active'}]);
      }
      return MockHttpResponse.ok();
    }, token: 'tk');

    await provider.fetchAssignedJobs('tk');
    await provider.completeJob('j');

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/complete'));
    expect(jsonDecode(posted.body!)['cash_collected'], isFalse);
  });

  test('completeJob omits requester_id when no token is set', () async {
    final (provider, overrides) = _makeProvider((req) {
      if (req.uri.path.endsWith('/users/jobs/get')) {
        return MockHttpResponse(200,
            jsonBody: [{'id': 'j', 'status': 'active'}]);
      }
      return MockHttpResponse.ok();
    });

    await provider.fetchAssignedJobs('');
    await provider.completeJob('j');

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/complete'));
    expect(jsonDecode(posted.body!).containsKey('requester_id'), isFalse);
  });

  test('completeJob on an unknown job id does not crash', () async {
    final (provider, _) =
        _makeProvider((req) => MockHttpResponse(200, jsonBody: []));

    await provider.fetchAssignedJobs('tk');
    await provider.completeJob('does-not-exist');

    expect(provider.jobs, isEmpty);
    expect(provider.error, isNull);
  });

  test('completeJob failure rethrows, sets friendly error, clears loading',
      () async {
    final (provider, _) = _makeProvider((req) {
      if (req.uri.path.endsWith('/users/jobs/get')) {
        return MockHttpResponse(200,
            jsonBody: [{'id': 'job-1', 'status': 'active'}]);
      }
      return MockHttpResponse(500, jsonBody: {'error': 'db down'});
    });

    await provider.fetchAssignedJobs('tk');
    await expectLater(
      provider.completeJob('job-1'),
      throwsA(isA<ApiClientException>()),
    );
    expect(provider.isLoading, isFalse);
    expect(provider.error,
        friendlyErrorMessage(ApiClientException('x', statusCode: 500)));
  });

  test('simulateAction posts email + action and rethrows failures', () async {
    var failNext = false;
    final (provider, overrides) = _makeProvider((req) {
      if (failNext) {
        return MockHttpResponse(403, jsonBody: {'error': 'account_frozen'});
      }
      return MockHttpResponse.ok();
    });

    await provider.simulateAction(email: 'e@x.dev', action: 'ARRIVED_PICKUP');
    final posted = overrides.requests.last;
    expect(posted.uri.path, endsWith('/auth/employee/action'));
    expect(jsonDecode(posted.body!),
        {'email': 'e@x.dev', 'action': 'ARRIVED_PICKUP'});

    failNext = true;
    await expectLater(
      provider.simulateAction(email: 'e@x.dev', action: 'X'),
      throwsA(isA<ApiClientException>()),
    );
    expect(provider.error,
        friendlyErrorMessage(ApiClientException('x', statusCode: 403)));
  });
}
