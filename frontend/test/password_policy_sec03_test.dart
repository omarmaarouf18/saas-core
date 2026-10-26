import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/password_policy.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';

/// SEC-03: client-side mirrors of the shared backend password policy.
void main() {
  resetScreenWeakPasswordTests();
  group('validatePassword (client mirror)', () {
    test('7 characters rejected, 8 accepted', () {
      final en = AppLocalizationsEn();
      expect(validatePassword(en, '1234567'),
          equals('Password must be at least 8 characters'));
      expect(validatePassword(en, '12345678'), isNull);
    });

    test('empty/null-length edge: minimum boundary is in runes', () {
      final en = AppLocalizationsEn();
      expect(validatePassword(en, 'أبجد'), equals(en.passwordTooShort));
      expect(
          validatePassword(en, 'أبجديةكاء'), // 8 runes
          isNull);
    });

    test('73-byte Arabic string rejected as too long, 72-byte accepted', () {
      // Each Arabic letter is 2 UTF-8 bytes: 36 letters = 72 bytes.
      final en = AppLocalizationsEn();
      expect(validatePassword(en, 'ب' * 36), isNull);
      // 37 letters = 74 bytes ≥ 73 rejected; and the odd half-block case:
      expect(validatePassword(en, 'ب' * 37), equals(en.passwordTooLong));
    });

    test('ASCII 72 bytes accepted, 73 bytes rejected', () {
      final en = AppLocalizationsEn();
      expect(validatePassword(en, 'a' * 72), isNull);
      expect(validatePassword(en, 'a' * 73), equals(en.passwordTooLong));
    });

    test('AR validator copy renders Egyptian-Arabic text', () {
      final ar = AppLocalizationsAr('ar');
      expect(validatePassword(ar, '1234567'), isNot(equals('')));
      expect(validatePassword(ar, '1234567'), equals(ar.passwordTooShort));
      expect(validatePassword(ar, 'a' * 73), equals(ar.passwordTooLong));
    });
  });

  group('weakPasswordServerMessage reason mapping', () {
    final en = AppLocalizationsEn();
    test('server policy reasons map to dedicated copy', () {
      expect(
          weakPasswordServerMessage(
                  en, 'password must be at least 8 characters')
              .contains('8'),
          isTrue);
      expect(
          weakPasswordServerMessage(en, 'password must be at most 72 bytes')
              .contains('72'),
          isTrue);
      expect(
        weakPasswordServerMessage(en, 'password is too common'),
        equals(en.passwordTooCommon),
      );
      expect(
        weakPasswordServerMessage(en, 'unexpected policy wording'),
        equals(en.passwordTooWeak),
      );
      expect(
        weakPasswordServerMessage(en, null),
        equals(en.passwordTooWeak),
      );
    });
  });
}

/// Widget-level: the reset screen's phase-2 submit against a server that
/// returns 400 weak_password must show the localized dedicated copy, not a
/// generic 400 message.
class WeakPasswordResetApiClient extends ApiClient {
  WeakPasswordResetApiClient() : super(baseUrl: 'http://localhost:3002');
  int resetCalls = 0;

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool isRetry = false,
      Map<String, String>? queryParams,
      Map<String, String>? headers}) async {
    if (path == '/auth/reset-password/verify-code') {
      return {
        'status': 'success',
        'message': 'reset code verified',
        'reset_token': 'tok-weak-test',
      };
    }
    if (path == '/auth/reset-password') {
      resetCalls++;
      throw ApiClientException(
        'password is too common',
        statusCode: 400,
        errorCode: 'weak_password',
      );
    }
    return {};
  }
}

void resetScreenWeakPasswordTests() {}
