import 'dart:convert' show utf8;

import '../l10n/app_localizations.dart';

/// SEC-03 client-side mirror of the shared backend password policy
/// (`shared/infra/passwordpolicy`): at least [minLength] (8) runes, at most
/// [maxLength] (72) UTF-8 bytes — counted in bytes so multi-byte Arabic
/// characters are measured correctly — returning the localized validation
/// message for the violated rule, or null when the password is compliant.
///
/// The common-password blocklist is server-side only (needs no client
/// oracle here); the app surfaces that outcome through the server's
/// `weak_password` response instead (see [weakPasswordServerMessage]).
const int minLength = 8;
const int maxLengthBytes = 72;

/// Returns the localized password-policy violation for [password] based on
/// what the *client* can check (length only), or null when compliant.
String? validatePassword(AppLocalizations l10n, String password) {
  final runes = password.runes.length;
  if (runes < minLength) {
    return l10n.passwordTooShort;
  }
  // Dart String.length counts UTF-16 code units; the policy cap is UTF-8
  // bytes (the bcrypt limit), so multi-byte Arabic input is measured via
  // utf8.encode.
  if (utf8.encode(password).length > maxLengthBytes) {
    return l10n.passwordTooLong;
  }
  return null;
}

/// Maps a server rejection carrying `code == "weak_password"` to a clear
/// localized message describing the reason the server gave, falling back
/// to the generic weak-password line. Never leaks raw server text.
String weakPasswordServerMessage(AppLocalizations l10n, String? reason) {
  final r = (reason ?? '').toLowerCase();
  if (r.contains('at least')) return l10n.passwordTooShort;
  if (r.contains('at most')) return l10n.passwordTooLong;
  if (r.contains('common')) return l10n.passwordTooCommon;
  return l10n.passwordTooWeak;
}
