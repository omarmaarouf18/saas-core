import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Test sandbox stub for OpenStreetMap raster tiles.
///
/// The sandbox `HttpClient` answers every request with HTTP 400, and
/// flutter_map rethrows tile failures to the image service. Any camera move
/// while tiles are in flight (open autofit, refit, zoom taps — including the
/// declarative `initialCameraFit`) disposes mid-flight tile requests, so
/// their errors escape tile handling and fail widget tests at teardown with
/// "Multiple exceptions". Screens whose camera never moves dodge this by
/// luck, not virtue.
///
/// Serving valid (1x1 transparent PNG) bytes keeps map widget tests
/// deterministic. Install in `setUp`, restore in `tearDown`; app error paths
/// (permission, markers, addresses) are unaffected.
final List<int> stubTilePngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class StubTileHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => StubTileHttpClient();
}

class StubTileHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      StubTileRequest(url);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class StubTileRequest implements HttpClientRequest {
  final Uri _uri;
  StubTileRequest(this._uri);

  @override
  Uri get uri => _uri;

  @override
  String get method => 'GET';

  @override
  HttpHeaders get headers => StubTileHeaders();

  @override
  Future<HttpClientResponse> close() async => StubTileResponse();

  // package:http pipes the (empty, for GET) body stream into the request
  // and awaits addStream — a noSuchMethod null would fail that await.
  @override
  Future<dynamic> addStream(Stream<List<int>> stream,
      {bool? cancelOnError}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class StubTileResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  StubTileResponse() : super(Stream.value(stubTilePngBytes));

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => stubTilePngBytes.length;

  @override
  HttpHeaders get headers => StubTileHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  String get reasonPhrase => 'OK';

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class StubTileHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
