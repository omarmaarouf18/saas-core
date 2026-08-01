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

  /// Callback fired when a token is successfully refreshed during HTTP 401 retry.
  Future<void> Function(String newToken)? onTokenRefreshed;

  /// Callback fired when token refresh fails or session is expired (>7 days / frozen).
  Future<void> Function()? onAuthFailed;

  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  ApiClient({
    this.baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://localhost:8080/api/v1',
    ),
  }) {
    // Setup security overrides for local developer self-signed certificates.
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = bypassBadCertificate;
    _client = io_client.IOClient(httpClient);
  }

  void setToken(String? token) {
    _jwtToken = token;
  }

  String? get currentToken => _jwtToken;

  Map<String, String> _getHeaders({String? overrideToken}) {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final tokenToUse = overrideToken ?? _jwtToken;
    if (tokenToUse != null && tokenToUse.isNotEmpty) {
      headers['Authorization'] = 'Bearer $tokenToUse';
    }
    return headers;
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool isRetry = false,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );
      return await _handleResponse(
        response,
        onRetry: isRetry ? null : () => post(path, body, isRetry: true),
        path: path,
      );
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParams,
    bool isRetry = false,
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client.get(
        uri,
        headers: _getHeaders(),
      );
      return await _handleResponse(
        response,
        onRetry: isRetry
            ? null
            : () => get(path, queryParams: queryParams, isRetry: true),
        path: path,
      );
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
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
      final streamedResponse = await _client.send(request);
      final response = await http.Response.fromStream(streamedResponse);
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
      final response = await _client.post(
        refreshUri,
        headers: _getHeaders(),
        body: jsonEncode({'token': _jwtToken}),
      );

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
