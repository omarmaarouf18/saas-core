import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';

/// Service photos (USER-AUTH-BE item 1, FE-BE-GAPS item 1).
///
/// The backend stores a storage key in `photo_url` (`services/<id>/photo.jpg`)
/// and serves the image at `GET /users/services/{id}/photo` to any signed-in
/// role (JWT in the Authorization header; no signed URL is returned).
/// `photo_version` (service JSON and upload response, PUSH-BE) changes
/// exactly when the photo does; the app sends it as `?v=` and keys its
/// cache by it (PUSH-FCM), so a replaced photo shows at once. The
/// upload is `POST /users/services/{id}/photo` (multipart field `photo`,
/// JPEG / PNG, at most 5 MB), or `POST /users/services/photo` without an id
/// before the service exists: the returned key is then sent as `photo_url`
/// on create.

/// Largest upload the server accepts (`5 << 20`).
const int kServicePhotoMaxBytes = 5 << 20;

/// Longest side the app scales a picked photo to before uploading.
const double kServicePhotoMaxSide = 1600;

/// JPEG quality used when the picker re-encodes the photo.
const int kServicePhotoQuality = 85;

/// Whether [photoUrl] is a stored photo the read endpoint can serve. Old
/// builds saved a device path (`file://…`, `/data/…`); the server clears
/// those on read, and the app never loads or sends one.
bool isStoredPhotoKey(String? photoUrl) {
  final p = photoUrl?.trim() ?? '';
  if (p.isEmpty) return false;
  return !(p.startsWith('file://') ||
      p.startsWith('/') ||
      p.startsWith(r'\') ||
      p.startsWith('./') ||
      p.startsWith('../') ||
      p.startsWith('content://'));
}

enum ServicePhotoFormat { jpeg, png }

/// The format from the first bytes, as the server checks it (JPEG
/// `FF D8 FF`, PNG `89 50 4E 47 0D 0A 1A 0A`). Null for anything else.
ServicePhotoFormat? servicePhotoFormatOf(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return ServicePhotoFormat.jpeg;
  }
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= png.length) {
    for (var i = 0; i < png.length; i++) {
      if (bytes[i] != png[i]) return null;
    }
    return ServicePhotoFormat.png;
  }
  return null;
}

enum ServicePhotoProblem { empty, notJpegOrPng, tooLarge }

/// The client-side check before an upload: JPEG or PNG and at most 5 MB
/// (after the picker scaled it down). Null when it can be sent.
ServicePhotoProblem? checkServicePhoto(List<int> bytes) {
  if (bytes.isEmpty) return ServicePhotoProblem.empty;
  if (servicePhotoFormatOf(bytes) == null) {
    return ServicePhotoProblem.notJpegOrPng;
  }
  if (bytes.length > kServicePhotoMaxBytes) return ServicePhotoProblem.tooLarge;
  return null;
}

/// File name sent with the upload (the server reads the bytes, not the
/// name, but keeps the extension consistent).
String servicePhotoFilename(List<int> bytes) =>
    servicePhotoFormatOf(bytes) == ServicePhotoFormat.png
        ? 'service.png'
        : 'service.jpg';

enum ServicePhotoFailure {
  /// 503, or the server's storage is not set up (500 "storage not
  /// initialized"): "photo upload unavailable right now".
  unavailable,

  /// 403 "...KYC approval is pending".
  kybNotApproved,

  /// 402 `upgrade_required`.
  paidPlanRequired,

  /// 400: the server refused the image (format, size, corrupt).
  rejected,

  /// Timeout or no connection.
  network,
  other,
}

ServicePhotoFailure servicePhotoFailureOf(Object error) {
  if (error is TimeoutException) return ServicePhotoFailure.network;
  if (error is! ApiClientException) return ServicePhotoFailure.other;
  final msg = error.message.toLowerCase();
  final status = error.statusCode;
  if (status == null) return ServicePhotoFailure.network;
  if (status == 503 || (status == 500 && msg.contains('storage'))) {
    return ServicePhotoFailure.unavailable;
  }
  if (status == 403 && msg.contains('kyc')) {
    return ServicePhotoFailure.kybNotApproved;
  }
  if (status == 402 || msg == 'upgrade_required') {
    return ServicePhotoFailure.paidPlanRequired;
  }
  if (status == 400) return ServicePhotoFailure.rejected;
  return ServicePhotoFailure.other;
}

/// Loads (with the JWT) and caches service photos, and uploads them.
/// One cached load per service, stored key and photo version; a failed
/// load is dropped from the cache so the next build tries again.
class ServicePhotoStore {
  ServicePhotoStore(this.apiClient);

  final ApiClient apiClient;
  final Map<String, Future<Uint8List?>> _cache = {};

  /// `photo_version` per stored key, as the server sent it (a function of
  /// the key, so it never goes stale).
  final Map<String, String> _versionOfKey = {};

  static String _cacheKey(String serviceId, String photoUrl, String? version) =>
      '$serviceId|$photoUrl|${version ?? ''}';

  /// The `photo_version` known for [photoUrl] (from a service or an
  /// upload), or null.
  String? versionOf(String? photoUrl) =>
      photoUrl == null ? null : _versionOfKey[photoUrl];

  /// The photo of [serviceId], or null when it has none / failed to load.
  /// [photoVersion] is the service's `photo_version` (null from old
  /// servers: then the key alone keys the cache, as before).
  Future<Uint8List?> load(String serviceId, String? photoUrl,
      {String? photoVersion}) {
    if (serviceId.isEmpty || !isStoredPhotoKey(photoUrl)) {
      return Future.value(null);
    }
    final v = photoVersion?.trim() ?? '';
    if (v.isNotEmpty) _versionOfKey[photoUrl!] = v;
    final version = versionOf(photoUrl);
    final key = _cacheKey(serviceId, photoUrl!, version);
    return _cache.putIfAbsent(key, () async {
      try {
        final bytes = await apiClient.getBytes(
            '/users/services/${Uri.encodeComponent(serviceId)}/photo',
            queryParams: version == null ? null : {'v': version});
        return servicePhotoFormatOf(bytes) == null ? null : bytes;
      } catch (e) {
        debugPrint('[ServicePhoto] load $serviceId failed: $e');
        _cache.remove(key);
        return null;
      }
    });
  }

  /// Uploads [bytes] and returns the stored key (`photo_url`). With a
  /// [serviceId] the server also saves it on the service; without one the
  /// key must be sent as `photo_url` when the service is created.
  Future<String> upload(
    List<int> bytes, {
    String? serviceId,
    void Function(double progress)? onProgress,
  }) async {
    final path = serviceId == null
        ? '/users/services/photo'
        : '/users/services/${Uri.encodeComponent(serviceId)}/photo';
    final res = await apiClient.postMultipart(
      path,
      fieldName: 'photo',
      fileBytes: bytes,
      filename: servicePhotoFilename(bytes),
      onProgress: onProgress == null
          ? null
          : (sent, total) =>
              onProgress(total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0)),
    );
    final key =
        res is Map ? (res['photo_url'] ?? res['key'])?.toString() : null;
    if (key == null || !isStoredPhotoKey(key)) {
      throw ApiClientException('photo upload returned no key', statusCode: 500);
    }
    final version = res is Map ? res['photo_version']?.toString().trim() : null;
    if (version != null && version.isNotEmpty) _versionOfKey[key] = version;
    if (serviceId != null) {
      invalidate(serviceId);
      _cache[_cacheKey(serviceId, key, versionOf(key))] =
          Future.value(Uint8List.fromList(bytes));
    }
    return key;
  }

  /// Forgets the cached photo of [serviceId] (replaced or removed). The key
  /// of a replaced photo is often the same (`services/<id>/photo.jpg`).
  void invalidate(String serviceId) {
    _cache.removeWhere((k, _) => k.startsWith('$serviceId|'));
  }
}

/// Provides the [ServicePhotoStore] to the pages below it. Without one
/// (tests, previews) photos show their placeholder.
class ServicePhotoScope extends InheritedWidget {
  const ServicePhotoScope(
      {super.key, required this.store, required super.child});

  final ServicePhotoStore store;

  static ServicePhotoStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicePhotoScope>()?.store;

  @override
  bool updateShouldNotify(ServicePhotoScope oldWidget) =>
      store != oldWidget.store;
}
