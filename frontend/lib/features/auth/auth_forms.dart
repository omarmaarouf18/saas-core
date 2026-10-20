import '../../core/password_policy.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';

/// Validators and error text shared by the redesigned auth and account
/// pages. Same rules as the old screens.

final RegExp _email =
    RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
final RegExp _nameChars = RegExp(r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$');

String? validateEmail(AppLocalizations l10n, String value) {
  final v = value.trim();
  if (v.isEmpty) return l10n.authEmailRequired;
  if (!_email.hasMatch(v)) return l10n.authEmailInvalid;
  return null;
}

/// Display name (username): 3–30 runes, letters (Latin or Arabic),
/// digits, spaces and `_`.
String? validateName(AppLocalizations l10n, String value) {
  final v = value.trim();
  if (v.isEmpty) return l10n.authNameRequired;
  final runes = v.runes.length;
  if (runes < 3) return l10n.authNameTooShort;
  if (runes > 30) return l10n.authNameTooLong;
  if (!_nameChars.hasMatch(v)) return l10n.authNameInvalid;
  return null;
}

/// New password: required, then the SEC-03 client checks (length only).
String? validateNewPassword(AppLocalizations l10n, String value) {
  if (value.isEmpty) return l10n.authPasswordRequired;
  return validatePassword(l10n, value);
}

/// Text direction of a free-text name: right to left when it starts with an
/// Arabic letter, else left to right; null (ambient) when empty.
bool? startsRtl(String value) {
  if (value.isEmpty) return null;
  final first = value.runes.first;
  return first >= 0x0600 && first <= 0x06FF;
}

/// The banner text for [auth]'s last failure, in the current language for
/// the policy rejections the server tags with a code (`weak_password`).
/// Other failures keep the provider's text (server copy for 429 lockouts
/// and the allowlisted credential messages, friendly text otherwise).
String? authErrorText(AppLocalizations l10n, AuthProvider auth) {
  final error = auth.error;
  if (error == null) return null;
  if (auth.lastErrorCode == 'weak_password') {
    return weakPasswordServerMessage(l10n, auth.lastErrorReason);
  }
  return error;
}
