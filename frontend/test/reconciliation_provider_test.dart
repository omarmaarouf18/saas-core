import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/providers/reconciliation_provider.dart';

import 'helpers/mock_http_harness.dart';

void main() {
  test('fetchQueue maps the queue list and toggles isLoading mid-flight',
      () async {
    final gate = Completer<MockHttpResponse>();
    installMockHttp((req) {
      expect(req.method, 'GET');
      expect(req.uri.path, endsWith('/users/jobs/reconciliation-queue'));
      return gate.future;
    });
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
    final provider = ReconciliationProvider(api);

    final future = provider.fetchQueue();
    await Future<void>.delayed(Duration.zero);
    expect(provider.isLoading, isTrue);

    gate.complete(MockHttpResponse(200, jsonBody: [
      {
        'id': 'job-1',
        'locked_escrow_amount': 42.5,
        'reconciliation_note': 'Distance mismatch',
        'payment_method': 'cod',
      },
      {'id': 'job-2'},
    ]));
    await future;

    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
    expect(provider.queue.length, 2);
    expect(provider.queue.first.id, 'job-1');
    expect(provider.queue.first.lockedEscrowAmount, 42.5);
    expect(provider.queue.first.reconciliationNote, 'Distance mismatch');
  });

  test('fetchQueue treats a non-list payload as an empty queue', () async {
    installMockHttp(
        (req) => MockHttpResponse(200, jsonBody: {'unexpected': true}));
    final provider =
        ReconciliationProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));

    await provider.fetchQueue();

    expect(provider.queue, isEmpty);
    expect(provider.error, isNull);
  });

  test('fetchQueue maps failures to the friendly status-code message',
      () async {
    installMockHttp((req) => MockHttpResponse(500, jsonBody: {
          'error': 'raw mongo internals that must never surface',
        }));
    final provider =
        ReconciliationProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));

    await provider.fetchQueue();

    expect(
      provider.error,
      friendlyErrorMessage(
          ApiClientException('x', statusCode: 500)),
    );
    expect(provider.error, isNot(contains('mongo')));
    expect(provider.isLoading, isFalse);
  });

  test('resolveJob posts job_id + decision and removes the resolved job',
      () async {
    final overrides = installMockHttp((req) {
      if (req.uri.path.endsWith('/reconciliation-queue')) {
        return MockHttpResponse(200,
            jsonBody: [{'id': 'job-1'}, {'id': 'job-2'}]);
      }
      return MockHttpResponse(200, jsonBody: {'ok': true});
    });
    final provider = ReconciliationProvider(
        ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't'));
    await provider.fetchQueue();
    expect(provider.queue.length, 2);

    final ok = await provider.resolveJob(
        jobId: 'job-1', decision: 'release_to_employee');

    expect(ok, isTrue);
    expect(provider.queue.map((j) => j.id), ['job-2']);
    expect(provider.error, isNull);

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/reconciliation-resolve'));
    expect(posted.method, 'POST');
    expect(jsonDecode(posted.body!),
        {'job_id': 'job-1', 'decision': 'release_to_employee'});
  });

  test('resolveJob keeps the queue and surfaces a friendly error on conflict',
      () async {
    var callCount = 0;
    installMockHttp((req) {
      callCount++;
      if (callCount == 1) {
        return MockHttpResponse(200, jsonBody: [
          {'id': 'job-1'}
        ]);
      }
      return MockHttpResponse(409, jsonBody: {'error': 'job_state_changed'});
    });
    final provider =
        ReconciliationProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));
    await provider.fetchQueue();

    final ok = await provider.resolveJob(
        jobId: 'job-1', decision: 'refund_to_customer');

    expect(ok, isFalse);
    expect(provider.queue.length, 1);
    expect(
      provider.error,
      friendlyErrorMessage(
          ApiClientException('x', statusCode: 409)),
    );
  });

  test('setError / clearError update the exposed error state', () async {
    final provider = ReconciliationProvider(
        ApiClient(baseUrl: 'https://ci.local/api/v1', appVersion: 't'));

    var notified = 0;
    provider.addListener(() => notified++);

    provider.setError('boom');
    expect(provider.error, 'boom');

    provider.clearError();
    expect(provider.error, isNull);
    expect(notified, 2);
  });
}
