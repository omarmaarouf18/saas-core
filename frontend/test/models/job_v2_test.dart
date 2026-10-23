import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/job.dart';

// FE-COURIER item 1: Job model v2 parsing (ADR-0028) is additive. A legacy
// payload parses exactly as before (every old field, v2 fields empty), and
// a v2 payload fills the new fields; malformed v2 values are ignored.

Map<String, dynamic> _legacy() => {
      'id': 'job-1',
      'owner_id': 'owner-1',
      'employee_id': 'emp-1',
      'user_id': 'user-1',
      'service_id': 'svc-1',
      'status': 'active',
      'location': {
        'latitude': 30.05,
        'longitude': 31.24,
        'address_note': '  Beside the kiosk  ',
      },
      'destination': {'latitude': 30.06, 'longitude': 31.22},
      'payment_method': 'cod',
      'suggested_price': 42,
      'agreed_price': 40.5,
      'proposed_by': 'employee',
      'offer_expires_at': '2026-10-19T12:00:00Z',
      'offered_employee_ids': ['emp-1'],
      'cancellation_request_status': 'pending',
      'created_at': '2026-10-19T11:00:00Z',
      'updated_at': '2026-10-19T11:30:00Z',
    };

void main() {
  group('legacy payload', () {
    test('old fields parse as before and v2 fields stay empty', () {
      final job = Job.fromJson(_legacy());
      expect(job.id, 'job-1');
      expect(job.ownerId, 'owner-1');
      expect(job.employeeId, 'emp-1');
      expect(job.status, 'active');
      expect(job.location.latitude, 30.05);
      expect(job.location.addressNote, 'Beside the kiosk');
      expect(job.destination!.addressNote, isNull);
      expect(job.paymentMethod, 'cod');
      expect(job.suggestedPrice, 42.0);
      expect(job.agreedPrice, 40.5);
      expect(job.proposedBy, 'employee');
      expect(job.offerExpiresAt, DateTime.utc(2026, 10, 19, 12));
      expect(job.offeredEmployeeIds, ['emp-1']);
      expect(job.cancellationRequestStatus, 'pending');
      expect(job.createdAt, DateTime.utc(2026, 10, 19, 11));

      expect(job.subStatus, isNull);
      expect(job.statusHistory, isEmpty);
      expect(job.estimatedDurationMinutes, isNull);
      expect(job.recipient, isNull);
      expect(job.packageDetails, isNull);
      expect(job.courierPhone, isNull);
      expect(job.distanceReview, isNull);
      expect(job.location.address, isNull);
    });

    test('legacy location toJson is unchanged', () {
      final loc = JobLocation.fromJson(
          {'latitude': 1.5, 'longitude': 2.5, 'address_note': 'Gate 3'});
      expect(loc.toJson(),
          {'latitude': 1.5, 'longitude': 2.5, 'address_note': 'Gate 3'});
      expect(loc.addressSummary(), 'Gate 3');
    });

    test('an empty object still parses (defaults as before)', () {
      final job = Job.fromJson({});
      expect(job.status, 'pending');
      expect(job.location.latitude, 0.0);
      expect(job.statusHistory, isEmpty);
    });
  });

  group('v2 payload', () {
    Map<String, dynamic> v2() => {
          ..._legacy(),
          'location': {
            'latitude': 30.05,
            'longitude': 31.24,
            'address': ' 15 Qasr El Nil St ',
            'address_note': 'Third floor',
          },
          'destination': {
            'latitude': 30.06,
            'longitude': 31.22,
            'address': '4 Tahrir St, Dokki',
          },
          'sub_status': 'heading_to_pickup',
          'estimated_duration_minutes': 12,
          'recipient': {
            'name': 'Mahmoud',
            'phone': '+201012345678',
            'notes': 'Call before arriving',
          },
          'package_details': {'size': 'Small', 'notes': 'Documents'},
          'courier_phone': '+201099998888',
          'distance_review': {
            'actual_km': 1.2,
            'booked_km': 6,
            'flagged_at': '2026-10-19T12:40:00Z',
            'source': 'complete_job',
          },
          'status_history': [
            {
              'status': 'pending_dispatch',
              'at': '2026-10-19T11:00:00Z',
              'actor_role': 'customer',
            },
            {
              'status': 'active',
              'sub_status': 'heading_to_pickup',
              'at': '2026-10-19T11:01:10Z',
              'actor_role': 'employee',
              'actor_id': 'emp-1',
            },
            {
              'status': 'completed',
              'at': '2026-10-19T11:32:00Z',
              'actor_role': 'employee',
              'reason': 'cash collected',
            },
          ],
        };

    test('every v2 field is read', () {
      final job = Job.fromJson(v2());
      expect(job.location.address, '15 Qasr El Nil St');
      expect(job.location.addressNote, 'Third floor');
      expect(job.destination!.address, '4 Tahrir St, Dokki');
      expect(job.subStatus, 'heading_to_pickup');
      expect(job.estimatedDurationMinutes, 12);
      expect(job.recipient!.name, 'Mahmoud');
      expect(job.recipient!.phone, '+201012345678');
      expect(job.recipient!.notes, 'Call before arriving');
      expect(job.packageDetails!.size, 'small');
      expect(job.packageDetails!.notes, 'Documents');
      expect(job.courierPhone, '+201099998888');
      expect(job.distanceReview!.actualKm, 1.2);
      expect(job.distanceReview!.bookedKm, 6.0);
      expect(job.distanceReview!.source, 'complete_job');
      expect(job.statusHistory, hasLength(3));
      expect(job.statusHistory[1].subStatus, 'heading_to_pickup');
      expect(job.statusHistory[1].actorId, 'emp-1');
      expect(job.statusHistory[2].reason, 'cash collected');
    });

    test('historyTimeOf finds a status, optionally by sub-status', () {
      final job = Job.fromJson(v2());
      expect(
          job.historyTimeOf('completed'), DateTime.utc(2026, 10, 19, 11, 32));
      expect(job.historyTimeOf('active', subStatus: 'heading_to_pickup'),
          DateTime.utc(2026, 10, 19, 11, 1, 10));
      expect(job.historyTimeOf('active', subStatus: 'picked_up'), isNull);
      expect(job.historyTimeOf('cancelled'), isNull);
    });

    test('address text is sent back only when present', () {
      final job = Job.fromJson(v2());
      expect(job.location.toJson()['address'], '15 Qasr El Nil St');
    });
  });

  group('malformed v2 values are ignored', () {
    test('wrong types and blank strings become null / empty', () {
      final job = Job.fromJson({
        ..._legacy(),
        'sub_status': '  ',
        'status_history': 'nope',
        'estimated_duration_minutes': 'soon',
        'recipient': {'name': ' ', 'phone': ''},
        'package_details': 'big',
        'courier_phone': 42,
        'distance_review': [1, 2],
      });
      expect(job.subStatus, isNull);
      expect(job.statusHistory, isEmpty);
      expect(job.recipient, isNull);
      expect(job.packageDetails, isNull);
      expect(job.courierPhone, isNull);
      expect(job.distanceReview, isNull);
    });

    test('history entries without a status or a valid time are dropped', () {
      final job = Job.fromJson({
        ..._legacy(),
        'status_history': [
          {'status': 'active', 'at': 'yesterday'},
          {'at': '2026-10-19T11:00:00Z'},
          'junk',
          {'status': 'completed', 'at': '2026-10-19T11:32:00Z'},
        ],
      });
      expect(job.statusHistory.map((e) => e.status), ['completed']);
    });
  });
}
