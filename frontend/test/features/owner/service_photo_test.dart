import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/service_photo_tile.dart';
import 'package:frontend/features/owner/service_photo_section.dart';
import 'package:frontend/features/owner/service_setup_page.dart';
import 'package:frontend/providers/service_photo_store.dart';
import 'package:frontend/ui/qd_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_service_photos.dart';
import 'owner_harness.dart';

/// Picker fake: returns [next] for the camera and the library.
class FakePhotoPicker extends ServicePhotoPicker {
  FakePhotoPicker(this.next);

  Uint8List? next;
  final List<ServicePhotoSource> sources = [];

  @override
  Future<Uint8List?> pick(ServicePhotoSource source) async {
    sources.add(source);
    return next;
  }
}

Map<String, dynamic> svc({String? photo}) => {
      'id': 'svc-1',
      'tenant_id': 'owner-1',
      'name': 'Nile Express',
      'category': 'delivery',
      'coverage_radius_km': 8,
      'tenant_base_price': 20,
      'tenant_price_per_km': 4.5,
      'latitude': 30.0444,
      'longitude': 31.2357,
      if (photo != null) 'photo_url': photo,
    };

Future<void> openSheetAndPick(WidgetTester tester, String choice) async {
  await tester.tap(find.byKey(const Key('own_service_photo_pick')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('own_service_photo_$choice')));
  await tester.pump();
}

void main() {
  group('photo rules', () {
    test('stored keys vs device paths', () {
      expect(isStoredPhotoKey('services/svc-1/photo.jpg'), isTrue);
      for (final local in [
        null,
        '',
        '  ',
        'file:///data/x.jpg',
        '/data/user/0/app/cache/logo.jpg',
        r'\\share\x.jpg',
        './x.jpg',
        '../x.jpg',
        'content://media/1',
      ]) {
        expect(isStoredPhotoKey(local), isFalse, reason: '$local');
      }
    });

    test('format by magic bytes, size limit 5 MB', () {
      final png = solidPng(4, 10, 20, 30);
      expect(servicePhotoFormatOf(png), ServicePhotoFormat.png);
      expect(servicePhotoFormatOf(fakeJpeg(10)), ServicePhotoFormat.jpeg);
      expect(servicePhotoFormatOf(utf8.encode('GIF89a....')), isNull);
      expect(checkServicePhoto(png), isNull);
      expect(checkServicePhoto(const []), ServicePhotoProblem.empty);
      expect(checkServicePhoto(utf8.encode('<svg/>')),
          ServicePhotoProblem.notJpegOrPng);
      expect(checkServicePhoto(fakeJpeg(kServicePhotoMaxBytes)), isNull);
      expect(checkServicePhoto(fakeJpeg(kServicePhotoMaxBytes + 1)),
          ServicePhotoProblem.tooLarge);
      expect(servicePhotoFilename(png), 'service.png');
      expect(servicePhotoFilename(fakeJpeg(3)), 'service.jpg');
    });

    test('upload failures', () {
      ApiClientException e(int? s, [String m = 'x']) =>
          ApiClientException(m, statusCode: s);
      expect(servicePhotoFailureOf(e(503)), ServicePhotoFailure.unavailable);
      expect(servicePhotoFailureOf(e(500, 'storage not initialized')),
          ServicePhotoFailure.unavailable);
      expect(servicePhotoFailureOf(e(403, 'owner KYC approval is pending')),
          ServicePhotoFailure.kybNotApproved);
      expect(servicePhotoFailureOf(e(402, 'upgrade_required')),
          ServicePhotoFailure.paidPlanRequired);
      expect(servicePhotoFailureOf(e(400, 'corrupt or invalid image')),
          ServicePhotoFailure.rejected);
      expect(servicePhotoFailureOf(e(null, 'Network error')),
          ServicePhotoFailure.network);
      expect(servicePhotoFailureOf(TimeoutException('t')),
          ServicePhotoFailure.network);
      expect(servicePhotoFailureOf(e(500, 'boom')), ServicePhotoFailure.other);
      expect(servicePhotoFailureOf(StateError('x')), ServicePhotoFailure.other);
    });
  });

  group('ServicePhotoStore (HTTP)', () {
    test('loads with the JWT once per service and key, retries a failure',
        () async {
      final png = solidPng(4, 1, 2, 3);
      final requests = <http.Request>[];
      var fail = true;
      final api = ApiClient(
        baseUrl: 'https://api.test/api/v1',
        client: MockClient((req) async {
          requests.add(req);
          if (fail) return http.Response('{"error":"x"}', 404);
          return http.Response.bytes(png, 200,
              headers: {'content-type': 'image/png'});
        }),
      )..setToken('cust-jwt');
      final store = ServicePhotoStore(api);

      expect(await store.load('svc-1', 'services/svc-1/photo.png'), isNull);
      fail = false;
      expect(await store.load('svc-1', 'services/svc-1/photo.png'), png);
      expect(await store.load('svc-1', 'services/svc-1/photo.png'), png);
      expect(requests, hasLength(2), reason: 'the failure is not cached');
      expect(requests.last.url.toString(),
          'https://api.test/api/v1/users/services/svc-1/photo');
      expect(requests.last.headers['Authorization'], 'Bearer cust-jwt');

      // A device path is never requested.
      expect(await store.load('svc-2', '/data/x.jpg'), isNull);
      expect(requests, hasLength(2));
    });

    test('a non-image response is no photo', () async {
      final store = ServicePhotoStore(ApiClient(
        baseUrl: 'https://api.test/api/v1',
        client: MockClient((_) async => http.Response('{"ok":true}', 200)),
      ));
      expect(await store.load('svc-1', 'services/svc-1/photo.jpg'), isNull);
    });

    test('upload: multipart "photo" to the service, key back, progress',
        () async {
      final png = solidPng(8, 200, 100, 0);
      late http.BaseRequest seen;
      late List<int> body;
      final api = ApiClient(
        baseUrl: 'https://api.test/api/v1',
        client: MockClient.streaming((req, stream) async {
          seen = req;
          body = await stream.toBytes();
          return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({
                'message': 'photo uploaded',
                'photo_url': 'services/svc-1/photo.png',
                'key': 'services/svc-1/photo.png',
              }))),
              200);
        }),
      )..setToken('owner-jwt');
      final store = ServicePhotoStore(api);
      final progress = <double>[];
      final key =
          await store.upload(png, serviceId: 'svc-1', onProgress: progress.add);
      expect(key, 'services/svc-1/photo.png');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/v1/users/services/svc-1/photo');
      expect(seen.headers['Authorization'], 'Bearer owner-jwt');
      final text = latin1.decode(body);
      expect(text, contains('name="photo"; filename="service.png"'));
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      // The new photo is served from the cache, without a request.
      expect(await store.load('svc-1', key), png);
    });

    test('upload before the service exists goes to /users/services/photo',
        () async {
      late Uri url;
      final store = ServicePhotoStore(ApiClient(
        baseUrl: 'https://api.test/api/v1',
        client: MockClient((req) async {
          url = req.url;
          return http.Response(
              jsonEncode({'photo_url': 'services/owner-1/photo_1.jpg'}), 200);
        }),
      ));
      expect(await store.upload(fakeJpeg(64)), 'services/owner-1/photo_1.jpg');
      expect(url.path, '/api/v1/users/services/photo');
    });

    test('a 503 surfaces as unavailable; a device path back is refused',
        () async {
      var status = 503;
      var reply = '{"error":"service_unavailable"}';
      final store = ServicePhotoStore(ApiClient(
        baseUrl: 'https://api.test/api/v1',
        client: MockClient((_) async => http.Response(reply, status)),
      ));
      await expectLater(
        store.upload(fakeJpeg(64), serviceId: 'svc-1'),
        throwsA(predicate((Object e) =>
            servicePhotoFailureOf(e) == ServicePhotoFailure.unavailable)),
      );
      status = 200;
      reply = '{"photo_url":"/sdcard/x.jpg"}';
      await expectLater(store.upload(fakeJpeg(64), serviceId: 'svc-1'),
          throwsA(isA<ApiClientException>()));
    });
  });

  group('OwnerServicePage photo', () {
    testWidgets('pick → check → upload with progress → shown', (tester) async {
      usePhone(tester);
      final photos = FakeServicePhotoStore()..uploadGate = Completer<void>();
      final deps = OwnerTestDeps(photos: photos);
      deps.owner.nextServices = [svc()];
      final picker = FakePhotoPicker(solidPng(16, 30, 120, 200));
      await pumpOwner(tester, deps, OwnerServicePage(photoPicker: picker),
          refresh: false);

      expect(find.text('Add photo'), findsOneWidget);
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
      await openSheetAndPick(tester, 'gallery');
      await tester.pump();
      expect(picker.sources, [ServicePhotoSource.gallery]);
      expect(
          find.byKey(const Key('own_service_photo_progress')), findsOneWidget);
      expect(find.text('Uploading… 40%'), findsOneWidget);

      photos.uploadGate!.complete();
      await tester.pumpAndSettle();
      expect(photos.uploads.single.serviceId, 'svc-1');
      expect(find.byKey(const Key('service_photo_image')), findsOneWidget);
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.byKey(const Key('own_service_photo_error')), findsNothing);

      // The upload saved it; the page's save does not send photo_url.
      await tester.tap(find.byKey(const Key('own_service_save')));
      await tester.pumpAndSettle();
      expect(deps.owner.updateCalls.single.containsKey('photo_url'), isFalse);
    });

    testWidgets('503 → "unavailable right now", retry uploads the same photo',
        (tester) async {
      usePhone(tester);
      final photos = FakeServicePhotoStore()
        ..nextUploadError =
            ApiClientException('service_unavailable', statusCode: 503);
      final deps = OwnerTestDeps(photos: photos);
      deps.owner.nextServices = [svc()];
      final png = solidPng(16, 30, 120, 200);
      await pumpOwner(
          tester, deps, OwnerServicePage(photoPicker: FakePhotoPicker(png)),
          refresh: false);

      await openSheetAndPick(tester, 'camera');
      await tester.pumpAndSettle();
      expect(
          find.text('Photo upload is unavailable right now. Try again later.'),
          findsOneWidget);
      expect(find.byKey(const Key('service_photo_image')), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(photos.uploads, hasLength(2));
      expect(photos.uploads.last.length, png.length);
      expect(find.byKey(const Key('own_service_photo_error')), findsNothing);
      expect(find.byKey(const Key('service_photo_image')), findsOneWidget);
    });

    testWidgets('too large / not an image: refused before any upload',
        (tester) async {
      usePhone(tester);
      final photos = FakeServicePhotoStore();
      final deps = OwnerTestDeps(photos: photos);
      deps.owner.nextServices = [svc()];
      final picker = FakePhotoPicker(fakeJpeg(kServicePhotoMaxBytes + 1));
      await pumpOwner(tester, deps, OwnerServicePage(photoPicker: picker),
          refresh: false);

      await openSheetAndPick(tester, 'gallery');
      await tester.pumpAndSettle();
      expect(find.text('This photo is over 5 MB. Choose a smaller one.'),
          findsOneWidget);
      picker.next = Uint8List.fromList(utf8.encode('GIF89a'));
      await openSheetAndPick(tester, 'gallery');
      await tester.pumpAndSettle();
      expect(find.text('Use a JPEG or PNG photo.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(photos.uploads, isEmpty);
    });

    testWidgets('a stored photo loads; remove clears photo_url',
        (tester) async {
      usePhone(tester);
      final photos =
          FakeServicePhotoStore(photos: {'svc-1': solidPng(8, 9, 9, 9)});
      final deps = OwnerTestDeps(photos: photos);
      deps.owner.nextServices = [svc(photo: 'services/svc-1/photo.png')];
      await pumpOwner(tester, deps, const OwnerServicePage(), refresh: false);

      expect(photos.loads, contains('svc-1'));
      expect(find.byKey(const Key('service_photo_image')), findsOneWidget);
      await openSheetAndPick(tester, 'remove');
      await tester.pumpAndSettle();
      expect(deps.owner.updateCalls.single,
          {'service_id': 'svc-1', 'owner_id': 'owner-1', 'photo_url': ''});
      expect(photos.invalidated, ['svc-1']);
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('a failed remove keeps the photo and offers retry',
        (tester) async {
      usePhone(tester);
      final photos =
          FakeServicePhotoStore(photos: {'svc-1': solidPng(8, 9, 9, 9)});
      final deps = OwnerTestDeps(photos: photos);
      deps.owner.nextServices = [svc(photo: 'services/svc-1/photo.png')];
      deps.owner.nextUpdateError = ApiClientException('boom', statusCode: 500);
      await pumpOwner(tester, deps, const OwnerServicePage(), refresh: false);

      await openSheetAndPick(tester, 'remove');
      await tester.pumpAndSettle();
      expect(find.text("We couldn't remove the photo. Try again."),
          findsOneWidget);
      expect(find.byKey(const Key('service_photo_image')), findsOneWidget);
      deps.owner.nextUpdateError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.owner.updateCalls, hasLength(2));
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
    });

    testWidgets('no photo store: placeholder, upload says unavailable',
        (tester) async {
      usePhone(tester);
      final deps = OwnerTestDeps();
      deps.owner.nextServices = [svc(photo: 'services/svc-1/photo.png')];
      await pumpOwner(tester, deps,
          OwnerServicePage(photoPicker: FakePhotoPicker(solidPng(4, 1, 1, 1))),
          refresh: false);
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsOneWidget);
      await openSheetAndPick(tester, 'gallery');
      await tester.pumpAndSettle();
      expect(
          find.text('Photo upload is unavailable right now. Try again later.'),
          findsOneWidget);
    });
  });

  group('ServicePhotoTile', () {
    testWidgets('placeholder when absent, failed or a device path',
        (tester) async {
      final photos =
          FakeServicePhotoStore(photos: {'ok': solidPng(4, 1, 2, 3)});
      Widget tile(String id, String? url) => ServicePhotoTile(
          key: Key('t_$id'), serviceId: id, photoUrl: url, name: 'Nile');
      await tester.pumpWidget(MaterialApp(
        theme: qdLightTheme,
        home: ServicePhotoScope(
          store: photos,
          child: Column(children: [
            tile('ok', 'services/ok/photo.png'),
            tile('missing', 'services/missing/photo.png'),
            tile('none', null),
            tile('local', 'file:///x.jpg'),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('service_photo_image')), findsOneWidget);
      expect(
          find.byKey(const Key('service_photo_placeholder')), findsNWidgets(3));
      expect(photos.loads, ['ok', 'missing']);
    });
  });
}
