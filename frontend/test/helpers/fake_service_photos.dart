import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/owner/service_photo_section.dart';
import 'package:frontend/providers/service_photo_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A valid [size]×[size] PNG of one colour (RGB), for photo tests and
/// goldens. Two diagonal bands so a golden shows the photo is drawn.
Uint8List solidPng(int size, int r, int g, int b) {
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filter: none
    for (var x = 0; x < size; x++) {
      final band = ((x + y) ~/ (size / 4).ceil()).isEven;
      raw.add(band ? [r, g, b] : [r ~/ 2, g ~/ 2, b ~/ 2]);
    }
  }
  Uint8List chunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    final out = BytesBuilder()
      ..add(_u32(data.length))
      ..add(typeBytes)
      ..add(data)
      ..add(_u32(_crc32([...typeBytes, ...data])));
    return out.toBytes();
  }

  final ihdr = [
    ..._u32(size),
    ..._u32(size),
    8, // bit depth
    2, // colour type: RGB
    0, 0, 0,
  ];
  return (BytesBuilder()
        ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(chunk('IHDR', ihdr))
        ..add(chunk('IDAT', ZLibCodec().encode(raw.toBytes())))
        ..add(chunk('IEND', const [])))
      .toBytes();
}

List<int> _u32(int v) =>
    [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// Minimal JPEG header bytes (not decodable; enough for the format check).
Uint8List fakeJpeg(int length) {
  final b = Uint8List(length);
  b[0] = 0xFF;
  b[1] = 0xD8;
  b[2] = 0xFF;
  return b;
}

/// [ServicePhotoStore] without a network: [photos] by service id, uploads
/// recorded, the next upload's failure and a gate to hold it open.
class FakeServicePhotoStore extends ServicePhotoStore {
  FakeServicePhotoStore({Map<String, Uint8List>? photos})
      : photos = photos ?? {},
        super(
            ApiClient(client: MockClient((_) async => http.Response('', 404))));

  final Map<String, Uint8List> photos;
  final List<String> loads = [];
  final List<({String? serviceId, int length})> uploads = [];
  final List<String> invalidated = [];
  Object? nextUploadError;
  Completer<void>? uploadGate;
  String nextKey = 'services/svc-1/photo.png';

  @override
  Future<Uint8List?> load(String serviceId, String? photoUrl) async {
    if (!isStoredPhotoKey(photoUrl)) return null;
    loads.add(serviceId);
    return photos[serviceId];
  }

  @override
  Future<String> upload(List<int> bytes,
      {String? serviceId, void Function(double progress)? onProgress}) async {
    uploads.add((serviceId: serviceId, length: bytes.length));
    onProgress?.call(0.4);
    if (uploadGate != null) await uploadGate!.future;
    final error = nextUploadError;
    if (error != null) {
      nextUploadError = null;
      throw error;
    }
    onProgress?.call(1);
    if (serviceId != null) photos[serviceId] = Uint8List.fromList(bytes);
    return nextKey;
  }

  @override
  void invalidate(String serviceId) {
    invalidated.add(serviceId);
    photos.remove(serviceId);
  }
}

/// Decodes every [Image] on screen (memory images decode off the fake
/// clock), then pumps, so goldens show the photos.
Future<void> precacheShownImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
}

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
