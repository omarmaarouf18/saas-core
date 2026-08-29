import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('maps ApiClientException status codes correctly (table-driven)', () {
      final cases = [
        (
          ApiClientException('invalid_credentials', statusCode: 400),
          "Please check your input and try again."
        ),
        (
          ApiClientException('invalid_credentials', statusCode: 401),
          "Incorrect login details."
        ),
        (
          ApiClientException('forbidden_action', statusCode: 403),
          "You're not allowed to do that."
        ),
        (
          ApiClientException('service_not_found', statusCode: 404),
          "This item isn't available."
        ),
        (
          ApiClientException('proposal_already_submitted', statusCode: 409),
          "Something changed — please refresh and try again."
        ),
        (
          ApiClientException('no_couriers_available', statusCode: 422),
          "No couriers are currently available in your area. Please try again shortly."
        ),
        (
          ApiClientException('rate_limit_exceeded', statusCode: 429),
          "That went through already — no need to tap again."
        ),
        (
          ApiClientException('internal_server_error', statusCode: 500),
          "Something went wrong on our end. Please try again shortly."
        ),
        (
          ApiClientException('bad_gateway', statusCode: 502),
          "Something went wrong on our end. Please try again shortly."
        ),
        (
          ApiClientException('service_unavailable', statusCode: 503),
          "Something went wrong on our end. Please try again shortly."
        ),
        (
          ApiClientException('gateway_timeout', statusCode: 599),
          "Something went wrong on our end. Please try again shortly."
        ),
        (
          ApiClientException('unknown_code', statusCode: null),
          "Something went wrong. Please try again."
        ),
        (
          ApiClientException('im_a_teapot', statusCode: 418),
          "Something went wrong. Please try again."
        ),
      ];

      for (final (exception, expectedMessage) in cases) {
        expect(
          friendlyErrorMessage(exception),
          equals(expectedMessage),
          reason: 'Failed for statusCode: ${exception.statusCode}',
        );
      }
    });

    test('maps connectivity exceptions correctly', () {
      final cases = [
        const SocketException('Failed host lookup'),
        TimeoutException('Connection timed out'),
        const HttpException('Connection reset by peer'),
        const HandshakeException('Handshake failed'),
        const TlsException('TLS negotiation error'),
        http.ClientException('Client error during HTTP request'),
      ];

      for (final exception in cases) {
        expect(
          friendlyErrorMessage(exception),
          equals(
              "Couldn't connect. Please check your internet connection and try again."),
          reason: 'Failed for exception: ${exception.runtimeType}',
        );
      }
    });

    test('maps unrecognized errors to generic fallback', () {
      final cases = [
        const FormatException('Invalid JSON'),
        StateError('Bad state'),
        Exception('Raw exception text'),
        'Raw error string',
        12345,
        null,
      ];

      for (final err in cases) {
        expect(
          friendlyErrorMessage(err),
          equals("Something went wrong. Please try again."),
          reason: 'Failed for error type: ${err.runtimeType}',
        );
      }
    });

    test('never leaks raw backend error strings or status codes in output', () {
      final sampleBackendErrors = [
        ('invalid_credentials', 401),
        ('proposal_already_submitted', 409),
        ('user_not_found', 404),
        ('distance_mismatch', 400),
        ('employee_frozen', 403),
        ('rate_limit_exceeded', 429),
        ('db_connection_failed', 500),
      ];

      for (final (rawCode, statusCode) in sampleBackendErrors) {
        final exception = ApiClientException(rawCode, statusCode: statusCode);
        final result = friendlyErrorMessage(exception);

        expect(result.contains(rawCode), isFalse,
            reason: 'Leaked raw code "$rawCode"');
        expect(result.contains(statusCode.toString()), isFalse,
            reason: 'Leaked status code "$statusCode"');
        expect(result.contains('ApiClientException'), isFalse,
            reason: 'Leaked ApiClientException prefix');
      }
    });
  });
}
