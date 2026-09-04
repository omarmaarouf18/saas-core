import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/providers/marketplace_provider.dart';

import 'helpers/mock_http_harness.dart';

(MarketplaceProvider, MockHttpOverrides) _makeProvider(MockHttpHandler handler,
    {String? token}) {
  final overrides = installMockHttp(handler);
  final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
  if (token != null) api.setToken(token);
  return (MarketplaceProvider(api), overrides);
}

MockHttpResponse _jobEnvelope(String id, {String status = 'pending'}) =>
    MockHttpResponse(200, jsonBody: {
      'job': {
        'id': id,
        'status': status,
        'payment_method': 'cod',
        'locked_escrow_amount': 12.5,
      }
    });

MockHttpResponse _bareJob(String id, {String status = 'active'}) =>
    MockHttpResponse(200, jsonBody: {'id': id, 'status': status});

void main() {
  test('fetchServices parses the services envelope and forwards query params',
      () async {
    final (provider, overrides) = _makeProvider((req) {
      expect(req.uri.path, endsWith('/users/services'));
      return MockHttpResponse(200, jsonBody: {
        'services': [
          {
            'service_id': 'svc-1',
            'tenant_business_name': 'Cairo Bikes',
            'category': 'transport',
            'base_price': 10.0,
            'price_per_km': 2.0,
          },
        ],
      });
    });

    await provider.fetchServices(
        nearBy: false, lat: 30.1, lon: 31.2, radius: 25.0, sortBy: 'distance');

    final req = overrides.requests.single;
    expect(req.uri.queryParameters, {
      'near_by': 'false',
      'lat': '30.1',
      'lon': '31.2',
      'radius': '25.0',
      'sort_by': 'distance',
    });
    expect(provider.services.length, 1);
    expect(provider.error, isNull);
  });

  test('fetchServices surfaces friendly errors', () async {
    final (provider, _) = _makeProvider(
        (req) => MockHttpResponse(503, jsonBody: {'error': 'unavailable'}));

    await provider.fetchServices();

    expect(provider.error,
        friendlyErrorMessage(ApiClientException('x', statusCode: 503)));
  });

  test('bookJob posts the exact booking payload and exposes the booked job',
      () async {
    final (provider, overrides) =
        _makeProvider((req) => _jobEnvelope('QD-1'), token: 'cust-tok');

    final job = await provider.bookJob(
      serviceId: 'svc-9',
      userId: 'cust-tok',
      latitude: 30.05,
      longitude: 31.23,
      paymentMethod: 'cod',
    );

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/track'));
    expect(jsonDecode(posted.body!), {
      'service_id': 'svc-9',
      'user_id': 'cust-tok',
      'location': {'latitude': 30.05, 'longitude': 31.23},
      'payment_method': 'cod',
    });
    expect(job!.id, 'QD-1');
    expect(provider.bookedJob!.status, 'pending');
    expect(provider.error, isNull);
  });

  test('bookJob parses the job from a 201 escrow-failure response and keeps it',
      () async {
    // Real TrackJob contract: escrow-lock failure still returns 201 with BOTH
    // the generic warning (no balance disclosure) and the unfunded job.
    final (
      provider,
      _
    ) = _makeProvider((req) => MockHttpResponse(201, jsonBody: {
          'message': 'job created but escrow lock failed — deposit funds first',
          'warning':
              'escrow lock failed — owner must deposit funds before this booking can be funded',
          'escrow_amount': 47.35,
          'job': {'id': 'unfunded-1', 'status': 'pending'},
        }));

    final job = await provider.bookJob(
      serviceId: 's',
      userId: 'u',
      latitude: 1,
      longitude: 1,
      paymentMethod: 'cod',
    );

    expect(job!.id, 'unfunded-1');
    expect(provider.error, isNull); // warning is not an ApiClientException
  });

  test('bookJob rethrows failures with a friendly error attached', () async {
    final (provider, _) =
        _makeProvider((req) => MockHttpResponse(429, jsonBody: {
              'error': 'duplicate_request_in_progress',
            }));

    await expectLater(
      provider.bookJob(
          serviceId: 's',
          userId: 'u',
          latitude: 1,
          longitude: 1,
          paymentMethod: 'cod'),
      throwsA(isA<ApiClientException>()),
    );
    expect(provider.error,
        friendlyErrorMessage(ApiClientException('x', statusCode: 429)));
  });

  test('fetchJobStatus queries id + requester_id and updates bookedJob',
      () async {
    // Backend contract (GET /users/jobs/get): the BARE job object, no envelope.
    final (provider, overrides) =
        _makeProvider((req) => _bareJob('j1', status: 'active'));

    final job = await provider.fetchJobStatus('j1', 'tok');

    final req = overrides.requests.single;
    expect(req.uri.path, endsWith('/users/jobs/get'));
    // Contract from the GetJob resolution fix: id is the JOB id and must not
    // be shadowed by any token parameter.
    expect(req.uri.queryParameters['id'], 'j1');
    expect(req.uri.queryParameters['requester_id'], 'tok');
    expect(job!.status, 'active');
    expect(provider.bookedJob!.id, 'j1');
    expect(job.id, overrides.requests.single.uri.queryParameters['id']);
  });

  test('rateJob posts blind-rating payload and returns the response map',
      () async {
    final (provider, overrides) = _makeProvider(
        (req) => MockHttpResponse(200, jsonBody: {'other_party_rated': true}));

    final res = await provider.rateJob(
      jobId: 'j',
      ratedByToken: 'me',
      ratedUserId: 'them',
      stars: 5,
      comment: 'great',
    );

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/rate'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'j',
      'rated_by': 'me',
      'rated_user': 'them',
      'stars': 5,
      'comment': 'great',
    });
    expect(res['other_party_rated'], isTrue);
  });

  test('cancelJob rejects an empty reason BEFORE issuing any request',
      () async {
    final (provider, overrides) = _makeProvider((req) => MockHttpResponse.ok());

    await expectLater(
      provider.cancelJob(jobId: 'j', reason: '   ', userToken: 't'),
      throwsA(isA<ApiClientException>()),
    );

    expect(overrides.requests, isEmpty);
    expect(provider.error, equals('cancel_reason_required'));
  });

  test('cancelJob trims the reason, posts it, and flips the local job state',
      () async {
    var call = 0;
    final (provider, overrides) = _makeProvider((req) {
      call++;
      if (call == 1) return _bareJob('j9');
      return MockHttpResponse(200, jsonBody: {
        'message': 'job cancelled successfully',
        'job_id': 'j9',
        'status': 'cancelled',
      });
    }, token: 't');
    await provider.fetchJobStatus('j9', 't');

    final res = await provider.cancelJob(
        jobId: 'j9', reason: '  courier never arrived  ', userToken: 't');

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/cancel'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'j9',
      'reason': 'courier never arrived',
      'requester_id': 't',
    });
    expect(res['job_id'], 'j9');
    expect(res['status'], 'cancelled');
    expect(provider.bookedJob!.status, 'cancelled');
    expect(provider.bookedJob!.cancellationReason, 'courier never arrived');
  });

  test('proposePrice delegates to propose-price with the negotiated amount',
      () async {
    final (provider, overrides) = _makeProvider(
        (req) => _jobEnvelope('jt', status: 'awaiting_price_response'));

    final job = await provider.proposePrice(
        jobId: 'jt', proposedPrice: 88.8, userToken: 'tok');

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/propose-price'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'jt',
      'proposed_price': 88.8,
      'requester_token': 'tok',
    });
    expect(job!.status, 'awaiting_price_response');
  });

  test('respondPrice delegates to respond-price with accept/decline decision',
      () async {
    final (provider, overrides) =
        _makeProvider((req) => _jobEnvelope('jr', status: 'active'));

    final job = await provider.respondPrice(
        jobId: 'jr', decision: 'accept', userToken: 'tok');

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/respond-price'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'jr',
      'decision': 'accept',
      'requester_token': 'tok',
    });
    expect(job!.id, 'jr');
  });

  test('fetchCustomerJobs uses requester_token only when provided', () async {
    var call = 0;
    final (provider, overrides) = _makeProvider((req) {
      call++;
      if (call == 1) {
        expect(req.uri.queryParameters.containsKey('requester_token'), isFalse);
        return MockHttpResponse(200, jsonBody: [
          {'id': 'o1'},
          {'id': 'o2'}
        ]);
      }
      expect(req.uri.queryParameters['requester_token'], 'tk');
      return MockHttpResponse(200, jsonBody: []);
    });

    final first = await provider.fetchCustomerJobs();
    expect(first.map((j) => j.id), ['o1', 'o2']);

    final second = await provider.fetchCustomerJobs('tk');
    expect(second, isEmpty);
    expect(provider.customerJobs, isEmpty);
    expect(call, 2);
  });
}
