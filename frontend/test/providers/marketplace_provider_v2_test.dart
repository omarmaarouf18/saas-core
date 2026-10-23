import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/marketplace_provider.dart';

import '../helpers/mock_http_harness.dart';

// FE-V2-CONSUME item 2: bookJobWithDetails sends the job model v2 inputs
// (ADR-0028) only when filled in; bookJob is unchanged.
void main() {
  (MarketplaceProvider, MockHttpOverrides) make() {
    final overrides = installMockHttp((req) => MockHttpResponse(201, jsonBody: {
          'job': {'id': 'QD-2', 'status': 'pending_dispatch'}
        }));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
    api.setToken('cust-tok');
    return (MarketplaceProvider(api), overrides);
  }

  Map<String, dynamic> posted(MockHttpOverrides o) => jsonDecode(o.requests
      .lastWhere((r) => r.uri.path.endsWith('/users/jobs/track'))
      .body!) as Map<String, dynamic>;

  test('all v2 fields, trimmed', () async {
    final (p, o) = make();
    final job = await p.bookJobWithDetails(
      serviceId: 'svc-9',
      userId: 'cust-tok',
      latitude: 30.05,
      longitude: 31.23,
      destinationLatitude: 30.15,
      destinationLongitude: 31.33,
      paymentMethod: 'cod',
      pickupAddressNote: 'Floor 3',
      pickupAddress: ' 15 Kasr El Nil St ',
      destinationAddress: '4 Tahrir St, Dokki',
      recipient: const JobRecipient(
          name: ' Mahmoud ', phone: '+201012345678', notes: 'Call first'),
      packageDetails: const JobPackageDetails(size: 'small', notes: 'Papers'),
    );
    expect(posted(o), {
      'service_id': 'svc-9',
      'user_id': 'cust-tok',
      'location': {
        'latitude': 30.05,
        'longitude': 31.23,
        'address_note': 'Floor 3',
        'address': '15 Kasr El Nil St',
      },
      'destination': {
        'latitude': 30.15,
        'longitude': 31.33,
        'address': '4 Tahrir St, Dokki',
      },
      'payment_method': 'cod',
      'recipient': {
        'name': 'Mahmoud',
        'phone': '+201012345678',
        'notes': 'Call first',
      },
      'package_details': {'size': 'small', 'notes': 'Papers'},
    });
    expect(job!.id, 'QD-2');
  });

  test('empty v2 fields send the old request', () async {
    final (p, o) = make();
    await p.bookJobWithDetails(
      serviceId: 's',
      userId: 'u',
      latitude: 1,
      longitude: 1,
      destinationLatitude: 2,
      destinationLongitude: 2,
      paymentMethod: 'cod',
      pickupAddress: '  ',
      destinationAddress: '',
      recipient: const JobRecipient(name: ' '),
      packageDetails: const JobPackageDetails(),
    );
    expect(posted(o), {
      'service_id': 's',
      'user_id': 'u',
      'location': {'latitude': 1, 'longitude': 1},
      'destination': {'latitude': 2, 'longitude': 2},
      'payment_method': 'cod',
    });
  });

  test('partial recipient and package: only the set fields', () async {
    final (p, o) = make();
    await p.bookJobWithDetails(
      serviceId: 's',
      userId: 'u',
      latitude: 1,
      longitude: 1,
      destinationLatitude: 2,
      destinationLongitude: 2,
      paymentMethod: 'cod',
      recipient: const JobRecipient(phone: '01012345678'),
      packageDetails: const JobPackageDetails(notes: 'Fragile'),
    );
    final body = posted(o);
    expect(body['recipient'], {'phone': '01012345678'});
    expect(body['package_details'], {'notes': 'Fragile'});
  });

  test('a 400 code reaches the caller as the exception message', () async {
    final o = installMockHttp((req) => MockHttpResponse(400, jsonBody: {
          'error': 'recipient_phone_invalid',
          'message': 'recipient phone must be an Egyptian mobile or E.164',
        }));
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
    final p = MarketplaceProvider(api);
    await expectLater(
      p.bookJobWithDetails(
        serviceId: 's',
        userId: 'u',
        latitude: 1,
        longitude: 1,
        destinationLatitude: 2,
        destinationLongitude: 2,
        paymentMethod: 'cod',
        recipient: const JobRecipient(phone: '123'),
      ),
      throwsA(isA<ApiClientException>()
          .having((e) => e.statusCode, 'status', 400)
          .having((e) => e.message, 'message', 'recipient_phone_invalid')),
    );
    expect(o.requests, hasLength(1));
  });
}
