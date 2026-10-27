import 'dart:convert';

import '../../core/api_client.dart';
import '../../core/api_error_codes.dart';
import '../../core/error_messages.dart';
import '../../l10n/app_localizations.dart';
import '../../models/job.dart';

/// Booking inputs of job model v2 (ADR-0028 §2.1 / §2.2 / §2.7) and the
/// client checks that mirror user-service `validateV2BookingFields`
/// (JOB-V2-BE). Every field is optional; empty input sends nothing, so the
/// old booking request is unchanged when nothing is typed.

/// `location.address` / `destination.address`, runes (server: 250).
const int kAddressMaxLength = 250;

/// `address_note`: the server counts UTF-8 bytes, not characters
/// (`len(req.Location.AddressNote) > 500` in TrackJob), so 500 Arabic
/// letters are refused. The picker keeps its 500-character input cap; this
/// check catches what the server would refuse.
const int kAddressNoteMaxBytes = 500;

const int kRecipientNameMaxLength = 100;
const int kRecipientPhoneMaxLength = 20;
const int kRecipientNotesMaxLength = 200;
const int kPackageNotesMaxLength = 200;

/// Package sizes the server accepts; "not specified" sends no size.
const List<String> kPackageSizes = ['small', 'medium', 'large'];

final RegExp _egyptianMobile = RegExp(r'^(?:\+20|0)?1[0125][0-9]{8}$');
final RegExp _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');

/// Package details apply to delivery and shipping, not to rides.
bool packageApplies(String? category) =>
    switch (category?.trim().toLowerCase()) {
      'delivery' || 'shipping' => true,
      _ => false,
    };

/// Rides word the recipient as the passenger.
bool isRide(String? category) => category?.trim().toLowerCase() == 'transport';

/// The phone as it is sent: trimmed, spaces and dashes removed (the server
/// only trims, so "010 1234 5678" would be refused as typed).
String normalizePhone(String phone) =>
    phone.trim().replaceAll(RegExp(r'[\s-]'), '');

/// Same shapes as the server's `ValidRecipientPhone`: an Egyptian mobile
/// (`01x…`, `+201x…`, `1x…`) or E.164, at most 20 characters.
bool validRecipientPhone(String phone) {
  final p = normalizePhone(phone);
  if (p.isEmpty || p.length > kRecipientPhoneMaxLength) return false;
  return _egyptianMobile.hasMatch(p) || _e164.hasMatch(p);
}

int _runes(String s) => s.trim().runes.length;

enum BookingField {
  /// An address or landmark note on the route (the server's codes do not
  /// say which stop).
  route,
  recipientName,
  recipientPhone,
  recipientNotes,
  packageSize,
  packageNotes,
}

enum BookingProblem {
  tooLong,
  invalidPhone,
  invalidSize,
  noteTooLong,

  /// The server says a value is required (`*_required` codes).
  missing,
}

class BookingError {
  const BookingError(this.problem, [this.max]);

  final BookingProblem problem;
  final int? max;

  @override
  bool operator ==(Object other) =>
      other is BookingError && other.problem == problem && other.max == max;

  @override
  int get hashCode => Object.hash(problem, max);

  @override
  String toString() => 'BookingError($problem, $max)';
}

/// What the customer typed in the booking form (raw text).
class BookingExtras {
  const BookingExtras({
    this.pickupAddress,
    this.pickupNote,
    this.dropoffAddress,
    this.dropoffNote,
    this.someoneElse = false,
    this.recipientName = '',
    this.recipientPhone = '',
    this.recipientNotes = '',
    this.packageSize,
    this.packageNotes = '',
    this.withPackage = true,
  });

  final String? pickupAddress;
  final String? pickupNote;
  final String? dropoffAddress;
  final String? dropoffNote;

  /// "Someone else" receives it; false = "I am the recipient" (no
  /// recipient is sent).
  final bool someoneElse;
  final String recipientName;
  final String recipientPhone;
  final String recipientNotes;

  /// null = not specified.
  final String? packageSize;
  final String packageNotes;

  /// False for rides: no package is sent.
  final bool withPackage;

  /// The recipient to send; null when "I am the recipient" or all empty.
  JobRecipient? get recipient {
    if (!someoneElse) return null;
    String? t(String s) => s.trim().isEmpty ? null : s.trim();
    final phone = normalizePhone(recipientPhone);
    final r = JobRecipient(
      name: t(recipientName),
      phone: phone.isEmpty ? null : phone,
      notes: t(recipientNotes),
    );
    return r.isEmpty ? null : r;
  }

  /// The package details to send; null for rides or when nothing is set.
  JobPackageDetails? get package {
    if (!withPackage) return null;
    final notes = packageNotes.trim();
    if (packageSize == null && notes.isEmpty) return null;
    return JobPackageDetails(
        size: packageSize, notes: notes.isEmpty ? null : notes);
  }
}

/// Client checks, in the server's order. Empty map = valid.
Map<BookingField, BookingError> validateBooking(BookingExtras b) {
  final errors = <BookingField, BookingError>{};
  for (final a in [b.pickupAddress, b.dropoffAddress]) {
    if (a != null && _runes(a) > kAddressMaxLength) {
      errors[BookingField.route] =
          const BookingError(BookingProblem.tooLong, kAddressMaxLength);
    }
  }
  if (!errors.containsKey(BookingField.route)) {
    for (final n in [b.pickupNote, b.dropoffNote]) {
      if (n != null && utf8.encode(n.trim()).length > kAddressNoteMaxBytes) {
        errors[BookingField.route] =
            const BookingError(BookingProblem.noteTooLong);
      }
    }
  }
  if (b.someoneElse) {
    if (_runes(b.recipientName) > kRecipientNameMaxLength) {
      errors[BookingField.recipientName] =
          const BookingError(BookingProblem.tooLong, kRecipientNameMaxLength);
    }
    if (b.recipientPhone.trim().isNotEmpty &&
        !validRecipientPhone(b.recipientPhone)) {
      errors[BookingField.recipientPhone] =
          const BookingError(BookingProblem.invalidPhone);
    }
    if (_runes(b.recipientNotes) > kRecipientNotesMaxLength) {
      errors[BookingField.recipientNotes] =
          const BookingError(BookingProblem.tooLong, kRecipientNotesMaxLength);
    }
  }
  if (b.withPackage) {
    if (b.packageSize != null && !kPackageSizes.contains(b.packageSize)) {
      errors[BookingField.packageSize] =
          const BookingError(BookingProblem.invalidSize);
    }
    if (_runes(b.packageNotes) > kPackageNotesMaxLength) {
      errors[BookingField.packageNotes] =
          const BookingError(BookingProblem.tooLong, kPackageNotesMaxLength);
    }
  }
  return errors;
}

/// The field a booking error is about, from the server's stable code
/// (USER-AUTH-BE item 10: `{"error": msg, "message": msg, "code": code}`;
/// older bodies put the code in `error`). The `*_required` codes are
/// listed by the backend task but not sent by TrackJob today (every v2
/// field is optional there); they are mapped so they land on their field
/// if they come. Null when the code is not about a field.
MapEntry<BookingField, BookingError>? serverBookingError(Object e) {
  if (e is! ApiClientException || e.statusCode != 400) return null;
  final code = stableErrorCode(e);
  return switch (code) {
    'address_required' =>
      const MapEntry(BookingField.route, BookingError(BookingProblem.missing)),
    'recipient_name_required' => const MapEntry(
        BookingField.recipientName, BookingError(BookingProblem.missing)),
    'recipient_phone_required' => const MapEntry(
        BookingField.recipientPhone, BookingError(BookingProblem.missing)),
    'package_details_required' => const MapEntry(
        BookingField.packageSize, BookingError(BookingProblem.missing)),
    'address_too_long' => const MapEntry(BookingField.route,
        BookingError(BookingProblem.tooLong, kAddressMaxLength)),
    'address_note_too_long' => const MapEntry(
        BookingField.route, BookingError(BookingProblem.noteTooLong)),
    'recipient_name_too_long' => const MapEntry(BookingField.recipientName,
        BookingError(BookingProblem.tooLong, kRecipientNameMaxLength)),
    'recipient_phone_invalid' => const MapEntry(
        BookingField.recipientPhone, BookingError(BookingProblem.invalidPhone)),
    'recipient_notes_too_long' => const MapEntry(BookingField.recipientNotes,
        BookingError(BookingProblem.tooLong, kRecipientNotesMaxLength)),
    'package_size_invalid' => const MapEntry(
        BookingField.packageSize, BookingError(BookingProblem.invalidSize)),
    'package_notes_too_long' => const MapEntry(BookingField.packageNotes,
        BookingError(BookingProblem.tooLong, kPackageNotesMaxLength)),
    _ => null,
  };
}

/// Localized text for a field error.
String bookingErrorText(
        AppLocalizations l10n, BookingField field, BookingError error) =>
    switch (error.problem) {
      BookingProblem.tooLong when field == BookingField.route =>
        l10n.bookErrAddressTooLong(error.max ?? kAddressMaxLength),
      BookingProblem.tooLong => l10n.bookErrTooLong(error.max ?? 0),
      BookingProblem.noteTooLong => l10n.bookErrNoteTooLong,
      BookingProblem.invalidPhone => l10n.bookErrPhone,
      BookingProblem.invalidSize => l10n.bookErrSize,
      BookingProblem.missing => switch (field) {
          BookingField.route => l10n.bookErrAddressRequired,
          BookingField.recipientName => l10n.bookErrNameRequired,
          BookingField.recipientPhone => l10n.bookErrPhoneRequired,
          BookingField.packageSize => l10n.bookErrPackageRequired,
          _ => l10n.bookErrRequired,
        },
    };

/// The banner text for a booking error that is not about one field: a
/// localized message for the stable codes the booking handlers send, the
/// server's own text for a code the app does not know, else the usual
/// friendly message (network, timeout, no body).
String bookingBannerText(AppLocalizations l10n, Object e) {
  final code = stableErrorCode(e);
  final known = switch (code) {
    'invalid_coordinates' => l10n.bookErrCoordinates,
    'payment_method_unavailable' => l10n.bookErrPayment,
    'duplicate_request_in_progress' => l10n.bookErrDuplicate,
    'service_unavailable' => l10n.bookErrUnavailable,
    'employee_location_unavailable' => l10n.bookErrNoCourier,
    _ => null,
  };
  if (known != null) return known;
  if (code != null) return serverErrorText(e) ?? friendlyErrorMessage(e);
  return friendlyErrorMessage(e);
}

/// Label of a package size ("not specified" for null / unknown).
String packageSizeLabel(AppLocalizations l10n, String? size) =>
    switch (size?.trim().toLowerCase()) {
      'small' => l10n.bookSizeSmall,
      'medium' => l10n.bookSizeMedium,
      'large' => l10n.bookSizeLarge,
      _ => l10n.bookSizeNone,
    };
