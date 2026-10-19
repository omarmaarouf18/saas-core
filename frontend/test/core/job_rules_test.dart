import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/job_rules.dart';
import 'package:frontend/models/job.dart';

Job _job(String id, String status, {DateTime? createdAt}) => Job(
      id: id,
      ownerId: 'o',
      userId: 'u',
      serviceId: 's',
      status: status,
      location: JobLocation(latitude: 30, longitude: 31),
      paymentMethod: 'cod',
      createdAt: createdAt,
    );

void main() {
  // Every backend status (services/user-service models.go JobStatus*), the
  // aliases the client already tolerates, and the frontend-only 'assigned'.
  const expected = <String, (bool ongoing, bool finished)>{
    'pending': (true, false),
    'pending_dispatch': (true, false),
    'awaiting_price_response': (true, false),
    'assigned': (true, false),
    'active': (true, false),
    'escrow_reconciliation_required': (true, false),
    'reconciliation_required': (true, false),
    'completed': (false, true),
    'cancelled': (false, true),
    'canceled': (false, true),
    'unavailable': (false, true),
  };

  expected.forEach((status, flags) {
    test('$status: ongoing=${flags.$1} finished=${flags.$2}', () {
      expect(isOngoingStatus(status), flags.$1);
      expect(isFinishedStatus(status), flags.$2);
      expect(isOngoing(_job('j', status)), flags.$1);
      expect(isFinished(_job('j', status)), flags.$2);
    });
  });

  test('case and surrounding space are ignored', () {
    expect(isOngoingStatus('  Awaiting_Price_Response '), isTrue);
    expect(isFinishedStatus('COMPLETED'), isTrue);
  });

  test('unknown, empty and null are neither ongoing nor finished', () {
    for (final s in ['teleported', '', '  ', null]) {
      expect(isOngoingStatus(s), isFalse, reason: '$s');
      expect(isFinishedStatus(s), isFalse, reason: '$s');
    }
  });

  test('ongoing and finished sets are disjoint', () {
    expect(kOngoingJobStatuses.intersection(kFinishedJobStatuses), isEmpty);
  });

  test('newestOngoingJob picks the newest ongoing job', () {
    final jobs = [
      _job('old', 'active', createdAt: DateTime(2026, 10, 1)),
      _job('done', 'completed', createdAt: DateTime(2026, 10, 18)),
      _job('new', 'awaiting_price_response', createdAt: DateTime(2026, 10, 17)),
      _job('undated', 'pending'),
    ];
    expect(newestOngoingJob(jobs)?.id, 'new');
    expect(newestOngoingJob([_job('c', 'cancelled')]), isNull);
    expect(newestOngoingJob(const []), isNull);
  });

  test('sortNewestFirst keeps undated jobs last in original order', () {
    final sorted = sortNewestFirst([
      _job('a', 'pending'),
      _job('b', 'pending', createdAt: DateTime(2026, 1, 1)),
      _job('c', 'pending'),
      _job('d', 'pending', createdAt: DateTime(2026, 2, 1)),
    ]);
    expect(sorted.map((j) => j.id), ['d', 'b', 'a', 'c']);
  });
}
