import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io_client;

class ApiClientException implements Exception {
  final int? statusCode;
  final String message;

  ApiClientException(this.message, {this.statusCode});

  @override
  String toString() => "ApiClientException: $message (status: $statusCode)";
}

bool bypassBadCertificate(X509Certificate cert, String host, int port) {
  // Strictly gate self-signed trust to local development / debug builds
  return kDebugMode &&
      (host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host == '10.0.3.2');
}

class ApiClient {
  final String baseUrl;
  late final http.Client _client;
  String? _jwtToken;
  String _appVersion = '1.0.0+1';

  /// Per-request ceiling (QA audit A5): without it a hung backend leaves
  /// every caller's loading state unresolved forever. Injectable so tests
  /// can exercise the expiry deterministically.
  final Duration requestTimeout;

  /// Callback fired when a token is successfully refreshed during HTTP 401 retry.
  Future<void> Function(String newToken)? onTokenRefreshed;

  /// Callback fired when token refresh fails or session is expired (>7 days / frozen).
  Future<void> Function()? onAuthFailed;

  /// Callback fired when backend returns HTTP 426 Upgrade Required.
  Future<void> Function(Map<String, dynamic>? info)? onUpdateRequired;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://localhost:8080/api/v1',
    ),
    String? appVersion,
    this.requestTimeout = const Duration(seconds: 30),
  }) {
    if (appVersion != null && appVersion.isNotEmpty) {
      _appVersion = appVersion;
    }
    // Setup security overrides for local developer self-signed certificates.
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = bypassBadCertificate;
    // Fail fast when nothing is listening at all (QA audit A5).
    httpClient.connectionTimeout = const Duration(seconds: 15);
    _client = io_client.IOClient(httpClient);
  }

  void setToken(String? token) {
    _jwtToken = token;
  }

  void setAppVersion(String version) {
    if (version.isNotEmpty) {
      _appVersion = version;
    }
  }

  String get appVersion => _appVersion;

  String? get currentToken => _jwtToken;

  Map<String, String> _getHeaders(
      {String? overrideToken, Map<String, String>? extraHeaders}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-App-Version': _appVersion,
    };
    final tokenToUse = overrideToken ?? _jwtToken;
    if (tokenToUse != null && tokenToUse.isNotEmpty) {
      headers['Authorization'] = 'Bearer $tokenToUse';
    }
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client
          .post(
            uri,
            headers: _getHeaders(extraHeaders: headers),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => post(path, body,
                queryParams: queryParams, headers: headers, isRetry: true),
        path: path,
      );
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client
          .put(
            uri,
            headers: _getHeaders(extraHeaders: headers),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => put(path, body,
                queryParams: queryParams, headers: headers, isRetry: true),
        path: path,
      );
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<dynamic> patch(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client
          .patch(
            uri,
            headers: _getHeaders(extraHeaders: headers),
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => patch(path, body,
                queryParams: queryParams, headers: headers, isRetry: true),
        path: path,
      );
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client
          .get(
            uri,
            headers: _getHeaders(extraHeaders: headers),
          )
          .timeout(requestTimeout);
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => get(path,
                queryParams: queryParams, headers: headers, isRetry: true),
        path: path,
      );
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<Uint8List> getBytes(
    String pathOrUrl, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
    bool isRetry = false,
  }) async {
    try {
      Uri uri;
      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        uri = Uri.parse(pathOrUrl);
      } else {
        uri = Uri.parse('$baseUrl$pathOrUrl');
      }
      if (queryParams != null && queryParams.isNotEmpty) {
        final existingParams = Map<String, String>.from(uri.queryParameters);
        existingParams.addAll(queryParams);
        uri = uri.replace(queryParameters: existingParams);
      }
      final response = await _client
          .get(
            uri,
            headers: _getHeaders(extraHeaders: headers),
          )
          .timeout(requestTimeout);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      throw ApiClientException(
          'Failed to load document (status: ${response.statusCode})',
          statusCode: response.statusCode);
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException('Network error: Unable to load document.');
    }
  }

  Future<dynamic> postMultipart(
    String path, {
    required String fieldName,
    required List<int> fileBytes,
    required String filename,
    bool isRetry = false,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));
      final headers = _getHeaders();
      request.headers.addAll(headers);
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          fileBytes,
          filename: filename,
        ),
      );
      final streamedResponse =
          await _client.send(request).timeout(requestTimeout);
      final response =
          await http.Response.fromStream(streamedResponse).timeout(
                requestTimeout,
              );
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => postMultipart(
                  path,
                  fieldName: fieldName,
                  fileBytes: fileBytes,
                  filename: filename,
                  isRetry: true,
                ),
        path: path,
      );
    } on TimeoutException {
      rethrow; // friendlyErrorMessage maps this to the connectivity copy.
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  /// Internal response handler with HTTP 401 token refresh interception logic.
  Future<dynamic> _handleResponse(
    http.Response response, {
    Future<dynamic> Function()? onRetry,
    required String path,
  }) async {
    dynamic body;
    try {
      if (response.body.isNotEmpty) {
        body = jsonDecode(response.body);
      }
    } catch (_) {
      // Body not decodable
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // Intercept HTTP 401 Unauthorized for silent token refresh
    final isAuthEndpoint = path.startsWith('/auth/login') ||
        path.startsWith('/auth/signup') ||
        path.startsWith('/auth/refresh') ||
        path.startsWith('/auth/logout') ||
        path.startsWith('/auth/forgot-password') ||
        path.startsWith('/auth/reset-password');

    if (response.statusCode == 426) {
      final info = body is Map<String, dynamic> ? body : null;
      onUpdateRequired?.call(info);
      String? errorMsg;
      if (body is Map) {
        errorMsg = body['message'] ?? body['error'];
      }
      throw ApiClientException(
        errorMsg ?? 'App update required',
        statusCode: 426,
      );
    }

    if (response.statusCode == 401 && !isAuthEndpoint && onRetry != null) {
      final refreshedToken = await _attemptTokenRefresh();
      if (refreshedToken != null) {
        return await onRetry();
      } else {
        // Refresh failed -> trigger auth failure callback
        onAuthFailed?.call();
      }
    }

    String? errorMsg;
    if (body is Map) {
      errorMsg = body['error'] ?? body['message'];
    }
    throw ApiClientException(
      errorMsg ?? 'Request failed',
      statusCode: response.statusCode,
    );
  }

  /// Thread-safe / concurrency-locked token refresh call to POST /auth/refresh.
  Future<String?> _attemptTokenRefresh() async {
    if (_isRefreshing) {
      return await _refreshCompleter?.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<String?>();

    try {
      if (_jwtToken == null || _jwtToken!.isEmpty) {
        _isRefreshing = false;
        _refreshCompleter?.complete(null);
        return null;
      }

      final refreshUri = Uri.parse('$baseUrl/auth/refresh');
      final response = await _client
          .post(
            refreshUri,
            headers: _getHeaders(),
            body: jsonEncode({'token': _jwtToken}),
          )
          .timeout(requestTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map && body['token'] is String) {
          final newToken = body['token'] as String;
          setToken(newToken);
          if (onTokenRefreshed != null) {
            await onTokenRefreshed!(newToken);
          }
          _refreshCompleter?.complete(newToken);
          _isRefreshing = false;
          return newToken;
        }
      }
    } catch (e) {
      debugPrint('[ApiClient] Token refresh attempt error: $e');
    }

    _refreshCompleter?.complete(null);
    _isRefreshing = false;
    return null;
  }

  Future<dynamic> proposePrice({
    required String jobId,
    required double proposedPrice,
    String? requesterToken,
  }) async {
    return post('/users/jobs/propose-price', {
      'job_id': jobId,
      'proposed_price': proposedPrice,
      if (requesterToken != null && requesterToken.isNotEmpty)
        'requester_token': requesterToken,
    });
  }

  Future<dynamic> respondPrice({
    required String jobId,
    required String decision,
    String? requesterToken,
  }) async {
    return post('/users/jobs/respond-price', {
      'job_id': jobId,
      'decision': decision,
      if (requesterToken != null && requesterToken.isNotEmpty)
        'requester_token': requesterToken,
    });
  }

  Future<dynamic> registerDeviceToken({
    required String token,
    String platform = 'android',
    String? action,
  }) async {
    return post('/auth/device-token', {
      'token': token,
      'platform': platform,
      if (action != null) 'action': action,
    });
  }

  Future<dynamic> unregisterDeviceToken({String? token}) async {
    return post('/auth/device-token', {
      'token': token ?? '',
      'action': 'unregister',
    });
  }
}
