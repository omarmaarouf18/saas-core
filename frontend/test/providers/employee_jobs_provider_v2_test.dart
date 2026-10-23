import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';

import '../helpers/mock_http_harness.dart';

// FE-COURIER additive provider changes: pickupJob (POST /users/jobs/pickup),
// completeJob's optional actual_cash_amount, and v2 fields surviving the
// provider's local rebuilds.

/// Same ordering contract as employee_jobs_provider_test.dart: install the
/// mock first, then build the ApiClient.
(EmployeeJobsProvider, MockHttpOverrides) _makeProvider(
    MockHttpHandler handler) {
  final overrides = installMockHttp(handler);
  final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
  api.setToken('emp-jwt');
  return (EmployeeJobsProvider(api), overrides);
}

Map<String, dynamic> _activeJob({String sub = 'heading_to_pickup'}) => {
      'id': 'job-1',
      'status': 'active',
      'sub_status': sub,
      'payment_method': 'cod',
      'suggested_price': 42,
      'recipient': {'name': 'Mahmoud', 'phone': '+201012345678'},
      'package_details': {'size': 'small'},
      'estimated_duration_minutes': 9,
      'status_history': [
        {'status': 'active', 'at': '2026-10-19T11:00:00Z'},
      ],
    };

MockHttpResponse _jobs(List<Map<String, dynamic>> list) =>
    MockHttpResponse(200, jsonBody: list);

void main() {
  group('pickupJob', () {
    test('posts job_id with the bearer token and takes the server job',
        () async {
      final (provider, overrides) = _makeProvider((req) {
        if (req.uri.path.endsWith('/users/jobs/get')) {
          return _jobs([_activeJob()]);
        }
        return MockHttpResponse(200, jsonBody: {
          'message': 'pickup recorded',
          'job': _activeJob(sub: 'picked_up'),
        });
      });
      await provider.fetchAssignedJobs('emp-jwt');

      final job = await provider.pickupJob('job-1');

      final posted = overrides.requests
          .lastWhere((r) => r.uri.path.endsWith('/users/jobs/pickup'));
      expect(posted.method, 'POST');
      expect(jsonDecode(posted.body!), {'job_id': 'job-1'});
      expect(posted.headers['authorization'], contains('Bearer emp-jwt'));
      expect(job!.subStatus, 'picked_up');
      expect(provider.jobs.single.subStatus, 'picked_up');
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
    });

    test('without a job in the response it is marked picked up locally',
        () async {
      final (provider, _) = _makeProvider((req) {
        if (req.uri.path.endsWith('/users/jobs/get')) {
          return _jobs([_activeJob()]);
        }
        return MockHttpResponse(200, jsonBody: {'message': 'pickup recorded'});
      });
      await provider.fetchAssignedJobs('emp-jwt');

      await provider.pickupJob('job-1');

      final j = provider.jobs.single;
      expect(j.subStatus, 'picked_up');
      expect(j.status, 'active');
      expect(j.recipient!.phone, '+201012345678');
      expect(j.packageDetails!.size, 'small');
      expect(j.estimatedDurationMinutes, 9);
      expect(j.statusHistory, hasLength(1));
    });

    test('409 already picked up is rethrown with its status code', () async {
      final (provider, _) = _makeProvider((req) {
        if (req.uri.path.endsWith('/users/jobs/get')) {
          return _jobs([_activeJob()]);
        }
        return MockHttpResponse(409,
            jsonBody: {'error': 'job already picked up'});
      });
      await provider.fetchAssignedJobs('emp-jwt');

      await expectLater(
          provider.pickupJob('job-1'),
          throwsA(isA<ApiClientException>()
              .having((e) => e.statusCode, 'statusCode', 409)));
      expect(provider.lastErrorStatusCode, 409);
      expect(provider.error, isNotNull);
      expect(provider.isLoading, isFalse);
      // The local entry is untouched.
      expect(provider.jobs.single.subStatus, 'heading_to_pickup');
    });

    test('403 (not the assigned courier) is rethrown', () async {
      final (provider, _) = _makeProvider((req) => MockHttpResponse(403,
              jsonBody: {
                'error': 'access denied: only the assigned courier can confirm'
              }));
      await expectLater(
          provider.pickupJob('job-1'),
          throwsA(isA<ApiClientException>()
              .having((e) => e.statusCode, 'statusCode', 403)));
      expect(provider.lastErrorStatusCode, 403);
    });
  });

  group('completeJob', () {
    test('sends actual_cash_amount only when positive', () async {
      final (provider, overrides) = _makeProvider((req) {
        if (req.uri.path.endsWith('/users/jobs/get')) {
          return _jobs([_activeJob(sub: 'picked_up')]);
        }
        return MockHttpResponse.ok();
      });
      await provider.fetchAssignedJobs('emp-jwt');

      await provider.completeJobWithAmount('job-1',
          cashCollected: true, actualCashAmount: 45.5);
      final first = overrides.requests
          .lastWhere((r) => r.uri.path.endsWith('/users/jobs/complete'));
      expect(jsonDecode(first.body!), {
        'job_id': 'job-1',
        'cash_collected': true,
        'actual_cash_amount': 45.5,
        'requester_id': 'emp-jwt',
      });

      await provider.completeJobWithAmount('job-1',
          cashCollected: true, actualCashAmount: 0);
      final second = overrides.requests
          .lastWhere((r) => r.uri.path.endsWith('/users/jobs/complete'));
      expect(
          (jsonDecode(second.body!) as Map).containsKey('actual_cash_amount'),
          isFalse);
    });

    test('the completed copy keeps the v2 fields and drops sub_status',
        () async {
      final (provider, _) = _makeProvider((req) {
        if (req.uri.path.endsWith('/users/jobs/get')) {
          return _jobs([_activeJob(sub: 'picked_up')]);
        }
        return MockHttpResponse.ok();
      });
      await provider.fetchAssignedJobs('emp-jwt');

      await provider.completeJob('job-1', cashCollected: true);

      final j = provider.jobs.single;
      expect(j.status, 'completed');
      expect(j.subStatus, isNull);
      expect(j.recipient!.name, 'Mahmoud');
      expect(j.statusHistory, hasLength(1));
    });
  });

  test('a cancellation request keeps the pickup phase', () async {
    final (provider, _) = _makeProvider((req) {
      if (req.uri.path.endsWith('/users/jobs/get')) {
        return _jobs([_activeJob(sub: 'picked_up')]);
      }
      return MockHttpResponse(200,
          jsonBody: {'cancellation_request_status': 'pending'});
    });
    await provider.fetchAssignedJobs('emp-jwt');

    await provider.requestCancellation(
        jobId: 'job-1', reason: 'Bike broke down', employeeToken: 'emp-jwt');

    final j = provider.jobs.single;
    expect(j.cancellationRequestStatus, 'pending');
    expect(j.subStatus, 'picked_up');
    expect(j.recipient!.phone, '+201012345678');
  });
}
