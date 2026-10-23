import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/providers/owner_provider.dart';

import '../../helpers/mock_http_harness.dart';

// FE-OWNER-1 additive OwnerProvider fields: raw owner job JSON (for the
// owner-only fields the shared Job model drops) and per-call errors.

void main() {
  OwnerProvider provider() =>
      OwnerProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));

  test('fetchOwnerJobs keeps the raw JSON of each job by id', () async {
    installMockHttp((req) {
      expect(req.uri.path, endsWith('/users/jobs/owner'));
      return MockHttpResponse.list([
        {
          'id': 'job-1',
          'status': 'completed',
          'payment_method': 'cod',
          'actual_cash_amount': 45.5,
          'distance_review': {
            'actual_km': 1.2,
            'booked_km': 4.0,
            'flagged_at': '2026-10-19T10:00:00Z',
            'source': 'complete_job',
          },
        },
        {'id': 'job-2', 'status': 'active'},
      ]);
    });
    final p = provider();
    await p.fetchOwnerJobs('owner-jwt');

    expect(p.ownerJobs.map((j) => j.id), ['job-1', 'job-2']);
    expect(p.ownerJobJson('job-1')?['actual_cash_amount'], 45.5);
    expect(
        (p.ownerJobJson('job-1')?['distance_review'] as Map)['booked_km'], 4.0);
    expect(p.ownerJobJson('job-2')?['actual_cash_amount'], isNull);
    expect(p.ownerJobJson('missing'), isNull);
    expect(p.ownerJobsError, isNull);
  });

  test('a failed fetchOwnerJobs keeps the last list and records its error',
      () async {
    var fail = false;
    installMockHttp((req) => fail
        ? MockHttpResponse(503, jsonBody: {'error': 'down'})
        : MockHttpResponse.list([
            {'id': 'job-1', 'status': 'active', 'actual_cash_amount': 10},
          ]));
    final p = provider();
    await p.fetchOwnerJobs('owner-jwt');
    fail = true;
    await p.fetchOwnerJobs('owner-jwt');

    expect(p.ownerJobsError, isNotNull);
    expect(p.ownerJobs.single.id, 'job-1');
    expect(p.ownerJobJson('job-1')?['actual_cash_amount'], 10);

    fail = false;
    await p.fetchOwnerJobs('owner-jwt');
    expect(p.ownerJobsError, isNull);
  });

  test('a non-list jobs payload clears the raw JSON too', () async {
    Object body = const <String, dynamic>{};
    installMockHttp((req) => MockHttpResponse(200, jsonBody: body));
    final p = provider();
    body = [
      {'id': 'job-1'}
    ];
    await p.fetchOwnerJobs('owner-jwt');
    expect(p.ownerJobJson('job-1'), isNotNull);
    body = {'unexpected': true};
    await p.fetchOwnerJobs('owner-jwt');
    expect(p.ownerJobs, isEmpty);
    expect(p.ownerJobJson('job-1'), isNull);
  });

  test('employeesError is set by fetchEmployees alone', () async {
    var employeesFail = true;
    installMockHttp((req) {
      if (req.uri.path.endsWith('/auth/employees')) {
        return employeesFail
            ? MockHttpResponse(500, jsonBody: {'error': 'db down'})
            : MockHttpResponse.list([
                {'id': 'emp-1', 'username': 'Karim', 'is_active': true},
              ]);
      }
      return MockHttpResponse.list([]);
    });
    final p = provider();
    await p.fetchEmployees('owner-jwt');
    expect(p.employeesError, isNotNull);

    // A later, successful call of another kind clears the shared [error]
    // but not the per-call error.
    await p.fetchOwnerJobs('owner-jwt');
    expect(p.error, isNull);
    expect(p.employeesError, isNotNull);
    expect(p.ownerJobsError, isNull);

    employeesFail = false;
    await p.fetchEmployees('owner-jwt');
    expect(p.employeesError, isNull);
    expect(p.employees.single['username'], 'Karim');
  });

  // FE-OWNER-2 additions.

  test('fetchServices records its own error and keeps the last list', () async {
    var fail = false;
    installMockHttp((req) {
      expect(req.uri.path, endsWith('/users/services'));
      return fail
          ? MockHttpResponse(500, jsonBody: {'error': 'boom'})
          : MockHttpResponse(200, jsonBody: {
              'services': [
                {'id': 'svc-1', 'tenant_id': 'owner-1'}
              ]
            });
    });
    final p = provider();
    await p.fetchServices();
    expect(p.servicesError, isNull);
    expect(p.services, hasLength(1));

    fail = true;
    await p.fetchServices();
    expect(p.servicesError, isNotNull);
    expect(p.services, hasLength(1));

    fail = false;
    await p.fetchServices();
    expect(p.servicesError, isNull);
  });

  test('fetchAuditLog records its own error and keeps the entries', () async {
    var fail = false;
    installMockHttp((req) {
      expect(req.uri.path, endsWith('/auth/audit-log'));
      expect(req.uri.queryParameters['tenant_id'], 'owner-1');
      return fail
          ? MockHttpResponse(500, jsonBody: {'error': 'boom'})
          : MockHttpResponse(200, jsonBody: {
              'entries': [
                {'id': 'a1', 'action': 'KYC_REVIEWED'}
              ]
            });
    });
    final p = provider();
    await p.fetchAuditLog(tenantId: 'owner-1', requesterToken: 'jwt');
    expect(p.auditLogError, isNull);
    fail = true;
    await p.fetchAuditLog(tenantId: 'owner-1', requesterToken: 'jwt');
    expect(p.auditLogError, isNotNull);
    expect(p.auditLogEntries, hasLength(1));
    fail = false;
    await p.fetchAuditLog(tenantId: 'owner-1', requesterToken: 'jwt');
    expect(p.auditLogError, isNull);
  });

  test('fetchDashboardData records its own error and keeps the values',
      () async {
    var failLedger = false;
    installMockHttp((req) {
      final path = req.uri.path;
      if (path.endsWith('/users/wallet')) {
        return MockHttpResponse(200, jsonBody: {
          'total_balance': 500,
          'escrow_balance': 120,
          'withdrawable_balance': 380,
        });
      }
      if (path.endsWith('/users/subscription')) {
        return MockHttpResponse(200, jsonBody: {'tier': 'paid'});
      }
      if (failLedger) return MockHttpResponse(500, jsonBody: {'error': 'x'});
      return MockHttpResponse(200, jsonBody: {
        'entries': [
          {'id': 'l1', 'type': 'deposit', 'amount': 10}
        ]
      });
    });
    final p = provider();
    await p.fetchDashboardData('owner-jwt');
    expect(p.dashboardError, isNull);
    expect(p.withdrawableBalance, 380);
    expect(p.ledgerEntries, hasLength(1));

    failLedger = true;
    await p.fetchDashboardData('owner-jwt');
    expect(p.dashboardError, isNotNull);
    expect(p.ledgerEntries, hasLength(1));

    failLedger = false;
    await p.fetchDashboardData('owner-jwt');
    expect(p.dashboardError, isNull);
  });
}
