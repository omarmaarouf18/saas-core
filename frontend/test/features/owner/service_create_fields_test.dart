import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/owner/service_rules.dart';
import 'package:frontend/features/owner/service_setup_page.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_service_photos.dart';
import 'owner_harness.dart';

/// A tiny user-service: POST /users/services stores the body as the
/// create handler does (USER-AUTH-BE item 2), GET returns what is stored.
class _ServicesBackend {
  final List<Map<String, dynamic>> stored = [];
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((req) async {
    requests.add(req);
    if (req.url.path.endsWith('/users/services') && req.method == 'POST') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final svc = {
        'id': 'svc-${stored.length + 1}',
        'tenant_id': body['owner_id'],
        for (final k in const [
          'name',
          'category',
          'tenant_base_price',
          'tenant_price_per_km',
          'latitude',
          'longitude',
          'photo_url',
          'address',
          'working_hours',
          'coverage_radius_km',
          'schedule_mode',
          'open_time',
          'close_time',
          'per_day_schedule',
          'timezone',
        ])
          if (body.containsKey(k)) k: body[k],
      };
      stored.add(svc);
      return http.Response(
          jsonEncode({'message': 'service created', 'service': svc}), 201);
    }
    if (req.url.path.endsWith('/users/services') && req.method == 'GET') {
      return http.Response(
          jsonEncode({'count': stored.length, 'services': stored}), 200);
    }
    return http.Response('{"error":"not found"}', 404);
  });
}

void main() {
  test('create → GET: every field of the draft is persisted by one POST',
      () async {
    final backend = _ServicesBackend();
    final owner = OwnerProvider(
        ApiClient(baseUrl: 'https://api.test/api/v1', client: backend.client));
    final hours = ServiceHours()
      ..setMode(ScheduleMode.perDay)
      ..days.first.off = true;
    final id = await saveService(owner,
        ownerId: 'owner-1',
        serviceId: null,
        d: ServiceDraft(
          name: 'Nile Express',
          category: 'shipping',
          latitude: 30.05,
          longitude: 31.24,
          address: '45 Nile Corniche, Maadi',
          radiusKm: 12.5,
          baseFee: 35,
          perKm: 4.5,
          schedule: scheduleFieldsOf(hours),
          photoUrl: 'services/owner-1/photo_1.jpg',
        ));

    expect(id, 'svc-1');
    expect(backend.requests.map((r) => '${r.method} ${r.url.path}'), [
      'POST /api/v1/users/services',
      'GET /api/v1/users/services',
    ]);
    final got = owner.services.single as Map<String, dynamic>;
    expect(got['address'], '45 Nile Corniche, Maadi');
    expect(got['coverage_radius_km'], 12.5);
    expect(got['photo_url'], 'services/owner-1/photo_1.jpg');
    expect(got['schedule_mode'], 'per_day');
    expect(got['per_day_schedule'], hasLength(7));
    expect((got['per_day_schedule'] as List).first, {
      'day': 'mon',
      'open_time': '09:00',
      'close_time': '17:00',
      'is_off': true
    });
    expect(got['tenant_base_price'], 35);
    expect(got['tenant_price_per_km'], 4.5);
    // The prefilled page reads the same values back.
    expect(ServiceHours.fromService(got).mode, ScheduleMode.perDay);
  });

  test('create: no schedule and no photo send none of those fields', () async {
    final backend = _ServicesBackend();
    final owner = OwnerProvider(
        ApiClient(baseUrl: 'https://api.test/api/v1', client: backend.client));
    await saveService(owner,
        ownerId: 'owner-1',
        serviceId: null,
        d: ServiceDraft(
          name: 'Nile',
          category: 'delivery',
          latitude: 30,
          longitude: 31,
          address: '',
          radiusKm: 5,
          baseFee: 0,
          perKm: 0,
          // Touched then cleared: "no schedule" on a new service.
          schedule: scheduleFieldsOf(ServiceHours()..clear()),
        ));
    final body = jsonDecode(backend.requests.first.body) as Map;
    expect(body.keys.toSet(), {
      'owner_id',
      'name',
      'category',
      'tenant_base_price',
      'tenant_price_per_km',
      'latitude',
      'longitude',
      'coverage_radius_km',
    });
  });

  testWidgets('a photo uploaded before the first save goes in the POST',
      (tester) async {
    usePhone(tester);
    final photos = FakeServicePhotoStore()
      ..nextKey = 'services/owner-1/photo_9.png';
    final deps = OwnerTestDeps(photos: photos);
    await tester.pumpWidget(ownerApp(
        deps,
        OwnerServicePage(
          pickPlace: (_, __) async =>
              const PickedPlace(latitude: 30.1, longitude: 31.3),
          photoPicker: FakePhotoPicker(solidPng(8, 1, 2, 3)),
        ),
        withData: false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('own_service_photo_pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('own_service_photo_gallery')));
    await tester.pumpAndSettle();
    expect(photos.uploads.single.serviceId, isNull);
    expect(
        find.text(
            'Photo ready. It is added to your service when you tap Save.'),
        findsOneWidget);

    await tester.enterText(find.byKey(const Key('own_service_name')), 'Nile');
    await tester.tap(find.byKey(const Key('own_service_place')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('own_service_radius')), '6');
    await tester.enterText(find.byKey(const Key('own_service_base_fee')), '15');
    await tester.enterText(find.byKey(const Key('own_service_per_km')), '3');
    await tester.tap(find.byKey(const Key('own_service_save')));
    await tester.pumpAndSettle();

    expect(deps.owner.createCalls.single['photo_url'],
        'services/owner-1/photo_9.png');
    expect(deps.owner.updateCalls, isEmpty);
  });
}
