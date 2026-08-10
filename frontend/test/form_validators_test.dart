import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Email Validator Accuracy Tests', () {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

    test('Rejects incomplete/invalid email addresses', () {
      expect(emailRegex.hasMatch('plainaddress'), isFalse);
      expect(emailRegex.hasMatch('#@%^%#\$@#\$@#.com'), isFalse);
      expect(emailRegex.hasMatch('@example.com'), isFalse);
      expect(emailRegex.hasMatch('Joe Smith <email@example.com>'), isFalse);
      expect(emailRegex.hasMatch('email.example.com'), isFalse);
      expect(emailRegex.hasMatch('email@example@example.com'), isFalse);
      expect(emailRegex.hasMatch('email@example'), isFalse);
      expect(emailRegex.hasMatch('a@b'), isFalse);
    });

    test('Accepts valid standard and international format email addresses', () {
      expect(emailRegex.hasMatch('user@example.com'), isTrue);
      expect(emailRegex.hasMatch('first.last@sub.domain.co'), isTrue);
      expect(emailRegex.hasMatch('user+tag@service.org'), isTrue);
    });
  });

  group('Username Validator Accuracy Tests', () {
    final usernameRegex = RegExp(r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$');

    test('Accepts valid Latin, Arabic, and mixed usernames', () {
      expect(usernameRegex.hasMatch('john_doe123'), isTrue);
      expect(usernameRegex.hasMatch('أحمد_عمر'), isTrue);
      expect(usernameRegex.hasMatch('User أحمد'), isTrue);
    });

    test('Rejects invalid special characters', () {
      expect(usernameRegex.hasMatch('user<script>'), isFalse);
      expect(usernameRegex.hasMatch('user@domain'), isFalse);
      expect(usernameRegex.hasMatch('user!#\$%'), isFalse);
    });

    test('Enforces length bounds (3 to 30 characters)', () {
      String? validate(String? val) {
        if (val == null || val.trim().isEmpty) return "Required";
        final trimmed = val.trim();
        final runes = trimmed.runes.length;
        if (runes < 3) return "Too short";
        if (runes > 30) return "Too long";
        if (!usernameRegex.hasMatch(trimmed)) return "Invalid characters";
        return null;
      }

      expect(validate('ab'), equals("Too short"));
      expect(validate('   ab   '), equals("Too short"));
      expect(validate('a' * 31), equals("Too long"));
      expect(validate('   '), equals("Required"));
      expect(validate('valid_user'), isNull);
      expect(validate('مستخدم_صحيح'), isNull);
    });
  });
}
