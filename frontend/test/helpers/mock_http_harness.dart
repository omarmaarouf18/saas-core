import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Recorded view of an outbound request for assertions.
class TestHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;

  TestHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  String? header(String name) => headers[name.toLowerCase()];
}

/// Canned response produced by a [MockHttpHandler].
class MockHttpResponse {
  final int statusCode;
  final Object? jsonBody;
  final String rawBody;

  MockHttpResponse(this.statusCode, {this.jsonBody, String? rawBody})
      : rawBody = rawBody ?? (jsonBody != null ? jsonEncode(jsonBody) : '');

  factory MockHttpResponse.list(List<dynamic> items) =>
      MockHttpResponse(200, jsonBody: items);

  factory MockHttpResponse.ok([Object? json]) =>
      MockHttpResponse(200, jsonBody: json);
}

typedef MockHttpHandler = FutureOr<MockHttpResponse> Function(
    TestHttpRequest request);

/// Process-wide fake dart:io HttpClient honoring [handler].
///
/// Works because ApiClient constructs `HttpClient()` directly, which routes
/// through HttpOverrides.global. Install AFTER
/// TestWidgetsFlutterBinding.ensureInitialized().
class MockHttpOverrides extends HttpOverrides {
  final MockHttpHandler handler;
  final List<TestHttpRequest> requests = [];

  MockHttpOverrides(this.handler);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(this);
}

/// Installs the overrides and returns them for request-recording assertions.
MockHttpOverrides installMockHttp(MockHttpHandler handler) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final overrides = MockHttpOverrides(handler);
  HttpOverrides.global = overrides;
  return overrides;
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> _values = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values[name.toLowerCase()] = value.toString();

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      add(name, value, preserveHeaderCase: preserveHeaderCase);

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  List<String>? operator [](String name) {
    final v = _values[name.toLowerCase()];
    return v == null ? null : [v];
  }

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  void clear() => _values.clear();

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach((k, v) => action(k, [v]));

  @override
  ContentType? contentType;

  @override
  int contentLength = 0;

  @override
  bool persistentConnection = true;

  @override
  bool chunkedTransferEncoding = false;

  @override
  String? host;

  @override
  int? port;

  @override
  DateTime? date;

  @override
  DateTime? ifModifiedSince;

  @override
  DateTime? expires;

  @override
  bool noFolding(String name) => true;
}

class _FakeHttpClient implements HttpClient {
  final MockHttpOverrides overrides;

  _FakeHttpClient(this.overrides);

  @override
  bool autoUncompress = true;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Duration? connectionTimeout;

  @override
  int? maxConnectionsPerHost;

  bool Function(X509Certificate cert, String host, int port)?
      _badCertificateCallback;

  /// Exposed for assertions that a bad-cert callback was wired by ApiClient.
  bool get hasBadCertificateHandler => _badCertificateCallback != null;

  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {
    _badCertificateCallback = callback;
  }

  @override
  set keyLog(void Function(String line)? callback) {}

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(method, url, this);

  // ---- convenience verbs (unused by package:http, required by interface) ----
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      openUrl('GET', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      openUrl('POST', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      openUrl('PUT', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      openUrl('DELETE', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      openUrl('HEAD', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      openUrl('PATCH', Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      openUrl(method, Uri.parse('https://$host:$port$path'));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  @override
  final String method;
  @override
  final Uri uri;
  final _FakeHttpClient client;
  final _FakeHeaders headerBag = _FakeHeaders();
  final BytesBuilder _body = BytesBuilder();
  final Completer<HttpClientResponse> _doneCompleter =
      Completer<HttpClientResponse>();

  _FakeRequest(this.method, this.uri, this.client);

  @override
  HttpHeaders get headers => headerBag;

  @override
  List<Cookie> cookies = [];

  @override
  bool bufferOutput = true;

  @override
  bool followRedirects = true;

  @override
  bool persistentConnection = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = 0;

  @override
  Future<HttpClientResponse> get done => _doneCompleter.future;

  @override
  void add(List<int> data) => _body.add(data);

  @override
  Future addStream(Stream<List<int>> stream) =>
      stream.forEach(_body.add).then((_) {});

  @override
  void write(Object? object, {Encoding encoding = utf8}) {
    if (object != null) _body.add(utf8.encode(object.toString()));
  }

  @override
  Future<HttpClientResponse> close() async {
    final recorded = TestHttpRequest(
      method: method,
      uri: uri,
      headers: Map<String, String>.from(headerBag._values),
      body: utf8.decode(_body.takeBytes(), allowMalformed: true),
    );
    client.overrides.requests.add(recorded);
    final mock = await client.overrides.handler(recorded);
    final response = _FakeResponse(
        statusCodeValue: mock.statusCode, bytes: utf8.encode(mock.rawBody));
    _doneCompleter.complete(response);
    return response;
  }

  @override
  Future<void> abort([Object? exception, StackTrace? stackTrace]) async {}

  @override
  HttpConnectionInfo? connectionInfo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  final int statusCodeValue;
  final List<int> bytes;
  final _FakeHeaders headerBag = _FakeHeaders();

  _FakeResponse({required this.statusCodeValue, required this.bytes});

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> element)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([bytes]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  int get contentLength => bytes.length;

  @override
  int get statusCode => statusCodeValue;

  @override
  String get reasonPhrase => '';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> redirects = const [];

  @override
  bool persistentConnection = true;

  @override
  List<Cookie> cookies = [];

  @override
  HttpHeaders get headers => headerBag;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) =>
      throw UnsupportedError('redirect not supported in mock');

  @override
  X509Certificate? certificate;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
