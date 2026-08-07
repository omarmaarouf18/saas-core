import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_client.dart';

/// Centralized user-friendly error message constants.
class ErrorMessages {
  static const String badRequest = "Please check your input and try again.";
  static const String unauthorized = "Incorrect login details.";
  static const String forbidden = "You're not allowed to do that.";
  static const String notFound = "This item isn't available.";
  static const String conflict =
      "Something changed — please refresh and try again.";
  static const String tooManyRequests =
      "That went through already — no need to tap again.";
  static const String serverError =
      "Something went wrong on our end. Please try again shortly.";
  static const String connectionError =
      "Couldn't connect. Please check your internet connection and try again.";
  static const String genericFallback =
      "Something went wrong. Please try again.";
}

/// Maps an exception/error object to a safe, user-facing English error string.
///
/// For [ApiClientException], mapping is based strictly on [ApiClientException.statusCode]
/// without inspecting or branching on backend error strings/codes.
/// Connectivity errors ([SocketException], [TimeoutException], etc.) return a connectivity message.
/// Unrecognized errors return a safe generic fallback.
String friendlyErrorMessage(Object? error) {
  if (error is ApiClientException) {
    final status = error.statusCode;
    if (status == 400) {
      return ErrorMessages.badRequest;
    } else if (status == 401) {
      return ErrorMessages.unauthorized;
    } else if (status == 403) {
      return ErrorMessages.forbidden;
    } else if (status == 404) {
      return ErrorMessages.notFound;
    } else if (status == 409) {
      return ErrorMessages.conflict;
    } else if (status == 429) {
      return ErrorMessages.tooManyRequests;
    } else if (status != null && status >= 500 && status <= 599) {
      return ErrorMessages.serverError;
    } else {
      return ErrorMessages.genericFallback;
    }
  }

  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is HandshakeException ||
      error is TlsException ||
      error is http.ClientException) {
    return ErrorMessages.connectionError;
  }

  return ErrorMessages.genericFallback;
}
