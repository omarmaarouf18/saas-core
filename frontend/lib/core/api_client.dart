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

  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    return headers;
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );
      return _handleResponse(response);
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$baseUrl$path');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _client.get(
        uri,
        headers: _getHeaders(),
      );
      return _handleResponse(response);
    } catch (e) {
      if (e is ApiClientException) rethrow;
      throw ApiClientException(
          "Network error: Please check your internet connection.");
    }
  }

  dynamic _handleResponse(http.Response response) {
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
    } else {
      String? errorMsg;
      if (body is Map) {
        errorMsg = body['error'] ?? body['message'];
      }
      throw ApiClientException(errorMsg ?? 'Request failed',
          statusCode: response.statusCode);
    }
  }
}
