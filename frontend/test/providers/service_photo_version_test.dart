import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/service_photo_tile.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/providers/service_photo_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fake_service_photos.dart';

// PUSH-FCM item 9: the photo URL carries `?v=<photo_version>` and the
// in-memory cache is keyed by it, so a replaced photo shows at once.

final _jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

class _Server {
  final List<Uri> photoGets = [];
  String nextUploadVersion = 'v2';

  ApiClient client() => ApiClient(
        baseUrl: 'https://ci.local/api/v1',
        client: MockClient((req) async {
          if (req.method == 'GET') {
            photoGets.add(req.url);
            return http.Response.bytes(_jpeg, 200,
                headers: {'content-type': 'image/jpeg'});
          }
          return http.Response(
              '{"message":"photo uploaded",'
              '"photo_url":"services/svc-1/photo-b.jpg",'
              '"key":"services/svc-1/photo-b.jpg",'
              '"photo_version":"$nextUploadVersion"}',
              200,
              headers: {'content-type': 'application/json'});
        }),
      );
}

void main() {
  group('ServicePhotoStore', () {
    test('sends ?v=<photo_version> and caches by it', () async {
      final server = _Server();
      final store = ServicePhotoStore(server.client());
      expect(
          await store.load('svc-1', 'services/svc-1/photo-a.jpg',
              photoVersion: 'aaaa1111'),
          _jpeg);
      await store.load('svc-1', 'services/svc-1/photo-a.jpg',
          photoVersion: 'aaaa1111');
      expect(server.photoGets, hasLength(1), reason: 'cached');
      final url = server.photoGets.single;
      expect(url.path, '/api/v1/users/services/svc-1/photo');
      expect(url.queryParameters, {'v': 'aaaa1111'});

      // A replaced photo: new key and version → fetched again at once.
      await store.load('svc-1', 'services/svc-1/photo-b.jpg',
          photoVersion: 'bbbb2222');
      expect(server.photoGets, hasLength(2));
      expect(server.photoGets.last.queryParameters, {'v': 'bbbb2222'});
    });

    test('the same key with a new version is not served from the cache',
        () async {
      final server = _Server();
      final store = ServicePhotoStore(server.client());
      const key = 'services/svc-1/photo.jpg';
      await store.load('svc-1', key, photoVersion: 'v1');
      await store.load('svc-1', key, photoVersion: 'v2');
      expect(server.photoGets.map((u) => u.queryParameters['v']),
          ['v1', 'v2']);
    });

    test('an old server without photo_version: no ?v=, cached by key',
        () async {
      final server = _Server();
      final store = ServicePhotoStore(server.client());
      await store.load('svc-1', 'services/svc-1/photo.jpg');
      await store.load('svc-1', 'services/svc-1/photo.jpg');
      expect(server.photoGets, hasLength(1));
      expect(server.photoGets.single.queryParameters, isEmpty);
    });

    test(
        'upload learns the new version: the uploaded bytes show at once, '
        'with or without the version', () async {
      final server = _Server()..nextUploadVersion = 'cafe0001';
      final store = ServicePhotoStore(server.client());
      await store.load('svc-1', 'services/svc-1/photo-a.jpg',
          photoVersion: 'aaaa1111');
      final key = await store.upload(_jpeg, serviceId: 'svc-1');
      expect(key, 'services/svc-1/photo-b.jpg');
      expect(store.versionOf(key), 'cafe0001');

      // Owner setup page (key from the upload, no version yet) and the
      // marketplace after a refresh (key + version from the server).
      expect(await store.load('svc-1', key), _jpeg);
      expect(await store.load('svc-1', key, photoVersion: 'cafe0001'), _jpeg);
      expect(server.photoGets, hasLength(1),
          reason: 'only the first, old photo was fetched');
    });
  });

  test('MarketplaceService reads photo_version', () {
    final s = MarketplaceService.fromJson({
      'id': 'svc-1',
      'photo_url': 'services/svc-1/photo.jpg',
      'photo_version': '0123456789abcdef',
    });
    expect(s.photoVersion, '0123456789abcdef');
    expect(MarketplaceService.fromJson({'id': 'x'}).photoVersion, isNull);
  });

  testWidgets('ServicePhotoTile reloads when photo_version changes',
      (tester) async {
    final store = FakeServicePhotoStore(photos: {'svc-1': _jpeg});
    Widget tile(String v) => Directionality(
          textDirection: TextDirection.ltr,
          child: ServicePhotoScope(
            store: store,
            child: ServicePhotoTile(
              serviceId: 'svc-1',
              photoUrl: 'services/svc-1/photo.jpg',
              photoVersion: v,
              name: 'Swift',
            ),
          ),
        );
    await tester.pumpWidget(tile('v1'));
    await tester.pumpWidget(tile('v1'));
    await tester.pumpWidget(tile('v2'));
    expect(store.loadVersions, ['v1', 'v2']);
  });
}
