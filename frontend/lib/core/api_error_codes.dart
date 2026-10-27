import 'api_client.dart';

/// Stable error codes (USER-AUTH-BE item 10). The services send them as
/// `{"error": "<text>", "message": "<text>", "code": "<code>"}`; older
/// handlers send the code itself as `error` (`{"error": "invalid_coordinates",
/// "message": ...}`).

final RegExp _codeLike = RegExp(r'^[a-z][a-z0-9_]*$');

/// The stable code of [error]: `code` (or `error.code`), else an `error`
/// string that is a code (lower snake case). Null for anything else.
String? stableErrorCode(Object error) {
  if (error is! ApiClientException) return null;
  final code = error.errorCode?.trim();
  if (code != null && code.isNotEmpty) return code;
  final msg = error.message.trim();
  return _codeLike.hasMatch(msg) && msg.contains('_') ? msg : null;
}

/// The server's own text for an error the app has no copy for: `message`,
/// else the `error` text. Null when the error is not an API error.
String? serverErrorText(Object error) {
  if (error is! ApiClientException) return null;
  final text = error.serverMessage ?? error.message;
  return text.trim().isEmpty ? null : text.trim();
}
