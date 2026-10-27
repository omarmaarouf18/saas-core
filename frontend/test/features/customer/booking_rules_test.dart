import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/booking_rules.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';

// FE-V2-CONSUME item 2: booking checks mirror user-service
// validateV2BookingFields; server 400 codes map to fields.
void main() {
  group('validRecipientPhone (server ValidRecipientPhone shapes)', () {
    for (final ok in [
      '01012345678',
      '01112345678',
      '01212345678',
      '01512345678',
      '+201012345678',
      '1012345678',
      '010 1234 5678',
      '010-1234-5678',
      '+447911123456',
    ]) {
      test('valid: $ok', () => expect(validRecipientPhone(ok), isTrue));
    }
    for (final bad in [
      '',
      '0101234567', // 9 digits after 01
      '01312345678', // 013 is not a mobile prefix
      '201012345678', // missing +
      '+0123456789',
      'phone',
      '+1234567', // E.164 needs 8+ digits after +
      '+1234567890123456', // too long
    ]) {
      test('invalid: $bad', () => expect(validRecipientPhone(bad), isFalse));
    }
    test('normalizePhone drops spaces and dashes', () {
      expect(normalizePhone(' 010 1234-5678 '), '01012345678');
    });
  });

  test('package applies to delivery and shipping only', () {
    expect(packageApplies('delivery'), isTrue);
    expect(packageApplies('Shipping'), isTrue);
    expect(packageApplies('transport'), isFalse);
    expect(packageApplies(null), isFalse);
    expect(isRide('transport'), isTrue);
  });

  group('validateBooking', () {
    test('everything empty is valid and sends nothing', () {
      const b = BookingExtras();
      expect(validateBooking(b), isEmpty);
      expect(b.recipient, isNull);
      expect(b.package, isNull);
    });

    test('"I am the recipient" ignores typed recipient fields', () {
      const b = BookingExtras(recipientName: 'x', recipientPhone: 'bad');
      expect(validateBooking(b), isEmpty);
      expect(b.recipient, isNull);
    });

    test('someone else: trimmed values, normalized phone', () {
      const b = BookingExtras(
          someoneElse: true,
          recipientName: ' Mahmoud ',
          recipientPhone: '010 1234 5678',
          recipientNotes: '  ');
      expect(validateBooking(b), isEmpty);
      expect(b.recipient!.name, 'Mahmoud');
      expect(b.recipient!.phone, '01012345678');
      expect(b.recipient!.notes, isNull);
    });

    test('someone else with nothing typed sends no recipient', () {
      expect(const BookingExtras(someoneElse: true).recipient, isNull);
    });

    test('limits in runes: 250 / 100 / 200 / 200', () {
      final ok = BookingExtras(
        pickupAddress: 'ش' * 250,
        dropoffAddress: 'a' * 250,
        someoneElse: true,
        recipientName: 'م' * 100,
        recipientNotes: 'n' * 200,
        packageNotes: 'p' * 200,
      );
      expect(validateBooking(ok), isEmpty);
      final bad = BookingExtras(
        dropoffAddress: 'a' * 251,
        someoneElse: true,
        recipientName: 'م' * 101,
        recipientPhone: '0123',
        recipientNotes: 'n' * 201,
        packageSize: 'huge',
        packageNotes: 'p' * 201,
      );
      expect(validateBooking(bad), {
        BookingField.route: const BookingError(BookingProblem.tooLong, 250),
        BookingField.recipientName:
            const BookingError(BookingProblem.tooLong, 100),
        BookingField.recipientPhone:
            const BookingError(BookingProblem.invalidPhone),
        BookingField.recipientNotes:
            const BookingError(BookingProblem.tooLong, 200),
        BookingField.packageSize:
            const BookingError(BookingProblem.invalidSize),
        BookingField.packageNotes:
            const BookingError(BookingProblem.tooLong, 200),
      });
    });

    test('landmark note: 500 characters, Arabic counted as characters', () {
      expect(validateBooking(BookingExtras(pickupNote: 'a' * 500)), isEmpty);
      // 500 Arabic letters are 1000 UTF-8 bytes: allowed (USER-AUTH-BE
      // item 9 counts runes).
      expect(validateBooking(BookingExtras(dropoffNote: 'ش' * 500)), isEmpty);
      expect(validateBooking(BookingExtras(dropoffNote: 'ش' * 501)), {
        BookingField.route: const BookingError(BookingProblem.noteTooLong),
      });
    });

    test('rides: no package checked or sent', () {
      const b = BookingExtras(
          withPackage: false, packageSize: 'huge', packageNotes: 'x');
      expect(validateBooking(b), isEmpty);
      expect(b.package, isNull);
    });

    test('package: size only, notes only', () {
      expect(const BookingExtras(packageSize: 'large').package!.size, 'large');
      final notesOnly = const BookingExtras(packageNotes: ' Fragile ').package!;
      expect(notesOnly.size, isNull);
      expect(notesOnly.notes, 'Fragile');
    });
  });

  group('serverBookingError', () {
    ApiClientException e400(String code) =>
        ApiClientException(code, statusCode: 400);

    test('every JOB-V2-BE code maps to its field', () {
      final expected = {
        'address_too_long': BookingField.route,
        'address_note_too_long': BookingField.route,
        'recipient_name_too_long': BookingField.recipientName,
        'recipient_phone_invalid': BookingField.recipientPhone,
        'recipient_notes_too_long': BookingField.recipientNotes,
        'package_size_invalid': BookingField.packageSize,
        'package_notes_too_long': BookingField.packageNotes,
      };
      expected.forEach((code, field) {
        expect(serverBookingError(e400(code))?.key, field, reason: code);
      });
    });

    test('a structured errorCode wins over the message', () {
      final e = ApiClientException('Bad',
          statusCode: 400, errorCode: 'package_size_invalid');
      expect(serverBookingError(e)?.key, BookingField.packageSize);
    });

    test('other errors are not field errors', () {
      expect(serverBookingError(e400('invalid_coordinates')), isNull);
      expect(
          serverBookingError(
              ApiClientException('recipient_phone_invalid', statusCode: 409)),
          isNull);
      expect(serverBookingError(Exception('x')), isNull);
    });
  });

  test('localized texts', () {
    final en = AppLocalizationsEn(), ar = AppLocalizationsAr();
    const long = BookingError(BookingProblem.tooLong, 100);
    expect(bookingErrorText(en, BookingField.recipientName, long),
        'Use at most 100 characters.');
    expect(bookingErrorText(ar, BookingField.recipientName, long),
        'اكتب 100 حرف بالكتير.');
    expect(
        bookingErrorText(en, BookingField.route,
            const BookingError(BookingProblem.tooLong, 250)),
        'An address is too long. Use at most 250 characters.');
    expect(packageSizeLabel(en, 'medium'), 'Medium');
    expect(packageSizeLabel(ar, 'large'), 'كبيرة');
    expect(packageSizeLabel(en, null), 'Not specified');
  });
}
