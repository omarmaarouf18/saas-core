import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/api_error_codes.dart';
import 'package:frontend/features/courier/courier_rules.dart';
import 'package:frontend/features/customer/booking_page.dart';
import 'package:frontend/features/customer/booking_rules.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'customer_harness.dart';

/// The error the real ApiClient throws for [body] with [status].
Future<ApiClientException> apiError(
    int status, Map<String, Object?> body) async {
  final api = ApiClient(
      baseUrl: 'https://api.test/api/v1',
      client: MockClient((_) async => http.Response(jsonEncode(body), status)));
  try {
    await api.post('/users/jobs/track', {});
  } on ApiClientException catch (e) {
    return e;
  }
  throw StateError('no error');
}

void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  group('ApiClient error shapes', () {
    test('{error, message, code}: code + server text kept', () async {
      final e = await apiError(400, {
        'error': 'recipient phone must be an Egyptian mobile or E.164 number',
        'message': 'recipient phone must be an Egyptian mobile or E.164 number',
        'code': 'recipient_phone_invalid',
      });
      expect(stableErrorCode(e), 'recipient_phone_invalid');
      expect(serverErrorText(e),
          'recipient phone must be an Egyptian mobile or E.164 number');
    });

    test('older {error: code, message}: the code, the message text', () async {
      final e = await apiError(400, {
        'error': 'invalid_coordinates',
        'message': 'Latitude must be between -90 and 90',
      });
      expect(stableErrorCode(e), 'invalid_coordinates');
      expect(serverErrorText(e), 'Latitude must be between -90 and 90');
    });

    test('a plain sentence is no code', () async {
      final e = await apiError(404, {'error': 'service not found'});
      expect(stableErrorCode(e), isNull);
      expect(stableErrorCode(Exception('x')), isNull);
    });
  });

  group('booking codes', () {
    ApiClientException e(String code, {int status = 400, String? text}) =>
        ApiClientException(text ?? code,
            statusCode: status, errorCode: code, serverMessage: text);

    test('every field code lands on its field, the required ones too', () {
      final expected = {
        'address_required': (BookingField.route, BookingProblem.missing),
        'address_too_long': (BookingField.route, BookingProblem.tooLong),
        'address_note_too_long': (
          BookingField.route,
          BookingProblem.noteTooLong
        ),
        'recipient_name_required': (
          BookingField.recipientName,
          BookingProblem.missing
        ),
        'recipient_name_too_long': (
          BookingField.recipientName,
          BookingProblem.tooLong
        ),
        'recipient_phone_required': (
          BookingField.recipientPhone,
          BookingProblem.missing
        ),
        'recipient_phone_invalid': (
          BookingField.recipientPhone,
          BookingProblem.invalidPhone
        ),
        'recipient_notes_too_long': (
          BookingField.recipientNotes,
          BookingProblem.tooLong
        ),
        'package_details_required': (
          BookingField.packageSize,
          BookingProblem.missing
        ),
        'package_size_invalid': (
          BookingField.packageSize,
          BookingProblem.invalidSize
        ),
        'package_notes_too_long': (
          BookingField.packageNotes,
          BookingProblem.tooLong
        ),
      };
      expected.forEach((code, want) {
        final got = serverBookingError(e(code));
        expect((got?.key, got?.value.problem), want, reason: code);
        // Every one has copy in both languages.
        expect(bookingErrorText(en, got!.key, got.value), isNotEmpty);
        expect(bookingErrorText(ar, got.key, got.value), isNotEmpty);
      });
      expect(
          bookingErrorText(en, BookingField.recipientPhone,
              const BookingError(BookingProblem.missing)),
          "Write the recipient's phone number.");
    });

    test('non-field codes: localized banner; unknown: the server text', () {
      expect(bookingBannerText(en, e('invalid_coordinates')),
          "The pickup or drop-off point isn't valid. Pick it again on the map.");
      expect(
          bookingBannerText(ar, e('payment_method_unavailable', status: 403)),
          'الدفع كاش عند الاستلام بس هو المتاح دلوقتي.');
      expect(
          bookingBannerText(
              en, e('duplicate_request_in_progress', status: 409)),
          contains('still being sent'));
      expect(bookingBannerText(en, e('service_unavailable', status: 503)),
          contains('unavailable'));
      expect(bookingBannerText(en, e('employee_location_unavailable')),
          contains('No courier'));
      expect(
          bookingBannerText(
              en,
              e('escrow_amount_unrecorded',
                  status: 500, text: 'Escrow not recorded.')),
          'Escrow not recorded.');
      // A field code on a non-400 is not a field error; it still gets text.
      expect(serverBookingError(e('address_too_long', status: 409)), isNull);
    });
  });

  group('pickup codes', () {
    ApiClientException e(String? code, int status, [String text = 'x']) =>
        ApiClientException(text,
            statusCode: status, errorCode: code, serverMessage: text);

    test('each stable code has its own copy', () {
      expect(pickupErrorText(en, e('already_picked_up', 409)),
          en.courPickupAlready);
      for (final c in ['job_not_active', 'job_state_changed', 'conflict']) {
        expect(pickupErrorText(en, e(c, 409)), en.courPickupChanged, reason: c);
      }
      expect(pickupErrorText(en, e('access_denied', 403)), en.courNotYours);
      expect(pickupErrorText(en, e('role_mismatch', 401)), en.courNotYours);
      expect(pickupErrorText(en, e('job_not_found', 404)), en.courJobGone);
      expect(
          pickupErrorText(en, e('job_id_required', 400, 'job_id is required')),
          'job_id is required');
      // No code: the status as before.
      expect(pickupErrorText(en, e(null, 409, 'Conflict happened')),
          en.courPickupAlready);
      expect(pickupErrorText(ar, e(null, 403, 'Forbidden')), ar.courNotYours);
    });
  });

  for (final (name, error, text) in [
    (
      'known code → localized banner',
      ApiClientException('invalid_coordinates',
          statusCode: 400,
          serverMessage: 'Latitude must be between -90 and 90'),
      "The pickup or drop-off point isn't valid. Pick it again on the map.",
    ),
    (
      'unknown code → the server text',
      ApiClientException('escrow_amount_unrecorded',
          statusCode: 500, serverMessage: 'Escrow amount was not recorded.'),
      'Escrow amount was not recorded.',
    ),
  ]) {
    testWidgets('booking page: $name', (tester) async {
      usePhone(tester);
      final deps = CustomerTestDeps()..marketplace.nextBookError = error;
      await tester.pumpWidget(customerApp(
          deps,
          CustomerBookingPage(
              service: service(),
              pickup: const PickedPlace(
                  latitude: 30.05, longitude: 31.24, isDeviceLocation: true))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose the drop-off place'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(FlutterMap), const Offset(-150, 120));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cust_picker_confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cust_book_submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cust_book_error')), findsOneWidget);
      expect(find.textContaining(text), findsOneWidget);
      expect(find.byKey(const Key('cust_book_route_error')), findsNothing);
    });
  }
}
