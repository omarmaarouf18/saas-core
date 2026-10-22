import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/owner/owner_rules.dart';
import 'package:frontend/models/job.dart';

Job _job(
  String id, {
  String status = 'active',
  String? employeeId,
  String payment = 'cod',
  DateTime? createdAt,
  String? requestStatus,
  DateTime? requestedAt,
}) =>
    Job(
      id: id,
      ownerId: 'owner-1',
      employeeId: employeeId,
      userId: 'user-1',
      serviceId: 'svc-1',
      status: status,
      location: JobLocation(latitude: 30, longitude: 31),
      paymentMethod: payment,
      createdAt: createdAt,
      cancellationRequestStatus: requestStatus,
      cancellationRequestedAt: requestedAt,
    );

const _karim = OwnerEmployee(
    id: 'emp-1', username: 'Karim', email: 'k@x.io', isActive: true);
const _frozen = OwnerEmployee(
    id: 'emp-2', username: 'Sara', email: 's@x.io', isActive: false);

void main() {
  final now = DateTime(2026, 10, 19, 15, 30);
  final today = DateTime(2026, 10, 19, 9);
  final yesterday = DateTime(2026, 10, 18, 22);

  group('ownerOrdersTabOf', () {
    for (final (status, tab) in [
      ('pending', OwnerOrdersTab.ongoing),
      ('pending_dispatch', OwnerOrdersTab.ongoing),
      ('awaiting_price_response', OwnerOrdersTab.ongoing),
      ('active', OwnerOrdersTab.ongoing),
      ('escrow_reconciliation_required', OwnerOrdersTab.ongoing),
      ('completed', OwnerOrdersTab.done),
      ('picked_up', OwnerOrdersTab.done),
      ('cancelled', OwnerOrdersTab.cancelled),
      (' Canceled ', OwnerOrdersTab.cancelled),
      ('unavailable', OwnerOrdersTab.cancelled),
    ]) {
      test('$status -> $tab', () {
        expect(ownerOrdersTabOf(_job('j', status: status)), tab);
      });
    }
  });

  test('owner cancel: pending and active only (as the old card)', () {
    final allowed = [
      for (final s in [
        'pending',
        'pending_dispatch',
        'awaiting_price_response',
        'active',
        'completed',
        'cancelled',
        'escrow_reconciliation_required',
        'unavailable',
      ])
        if (ownerCanCancel(_job('j', status: s))) s
    ];
    expect(allowed, ['pending', 'active']);
  });

  test('pending cancellation requests: ongoing only, oldest first', () {
    final jobs = [
      _job('late',
          requestStatus: 'pending', requestedAt: DateTime(2026, 10, 19, 12)),
      _job('early',
          requestStatus: 'pending', requestedAt: DateTime(2026, 10, 19, 10)),
      _job('stale', status: 'cancelled', requestStatus: 'pending'),
      _job('resolved', requestStatus: 'rejected'),
    ];
    expect(
        pendingCancellationRequests(jobs).map((j) => j.id), ['early', 'late']);
  });

  test('reconciliation count', () {
    expect(
        reconciliationCount([
          _job('a', status: 'escrow_reconciliation_required'),
          _job('b', status: 'reconciliation_required'),
          _job('c'),
        ]),
        2);
  });

  group('courier state', () {
    test('frozen wins over a current job', () {
      expect(
          courierStateOf(
              _frozen, [_job('j', employeeId: 'emp-2', status: 'active')]),
          CourierState.frozen);
    });
    test('on a job only for assigned / active orders', () {
      expect(
          courierStateOf(
              _karim, [_job('j', employeeId: 'emp-1', status: 'active')]),
          CourierState.onJob);
      expect(
          courierStateOf(_karim, [
            _job('j', employeeId: 'emp-1', status: 'completed'),
            _job('k',
                employeeId: 'emp-1', status: 'escrow_reconciliation_required'),
            _job('l', employeeId: 'emp-9', status: 'active'),
          ]),
          CourierState.free);
    });
    test('current job is the newest; jobs count is every loaded order', () {
      final jobs = [
        _job('old', employeeId: 'emp-1', createdAt: yesterday),
        _job('new', employeeId: 'emp-1', createdAt: today),
        _job('done', employeeId: 'emp-1', status: 'completed'),
      ];
      expect(currentJobOf('emp-1', jobs)?.id, 'new');
      expect(jobsCountOf('emp-1', jobs), 3);
      expect(jobsCountOf('emp-2', jobs), 0);
    });
  });

  group('todaySummary', () {
    OwnerJobExtras cash(Map<String, double?> amounts, String id) =>
        OwnerJobExtras(actualCashAmount: amounts[id]);

    test('counts today by created_at and sums recorded COD cash', () {
      final jobs = [
        _job('a', status: 'completed', createdAt: today),
        _job('b', status: 'completed', createdAt: today),
        _job('c', status: 'completed', createdAt: today, payment: 'wallet'),
        _job('d', status: 'active', createdAt: today),
        _job('e', status: 'completed', createdAt: yesterday),
        _job('f', status: 'pending', createdAt: yesterday),
      ];
      final s = todaySummary(
          jobs, (id) => cash({'a': 40, 'b': 25.5, 'e': 99}, id), now);
      expect(s.ongoingNow, 2);
      expect(s.ordersToday, 4);
      expect(s.deliveredToday, 3);
      expect(s.cashToday, 65.5);
      expect(s.truncated, isFalse);
    });

    test('no cash figure when a completed COD order has no amount', () {
      final s = todaySummary([
        _job('a', status: 'completed', createdAt: today),
        _job('b', status: 'completed', createdAt: today),
      ], (id) => cash({'a': 40}, id), now);
      expect(s.cashToday, isNull);
    });

    test('zero cash when nothing was delivered today', () {
      final s = todaySummary(
          [_job('a', createdAt: today)], (_) => OwnerJobExtras.none, now);
      expect(s.cashToday, 0);
      expect(s.deliveredToday, 0);
    });

    test('truncated when the server limit is reached with today only', () {
      final full = [
        for (var i = 0; i < kOwnerJobsServerLimit; i++)
          _job('j$i', createdAt: today)
      ];
      expect(todaySummary(full, (_) => OwnerJobExtras.none, now).truncated,
          isTrue);
      final mixed = [...full.skip(1), _job('old', createdAt: yesterday)];
      expect(todaySummary(mixed, (_) => OwnerJobExtras.none, now).truncated,
          isFalse);
    });
  });

  test('order search: id with or without #QD-, courier name', () {
    final j = _job('a1b2c3d4e5f6');
    expect(orderMatchesQuery(j, '', null), isTrue);
    expect(orderMatchesQuery(j, 'b2c3', null), isTrue);
    expect(orderMatchesQuery(j, '#QD-A1B2', null), isTrue);
    expect(orderMatchesQuery(j, 'kar', 'Karim'), isTrue);
    expect(orderMatchesQuery(j, 'zz', 'Karim'), isFalse);
  });

  test('extras parse actual cash and distance review', () {
    final x = OwnerJobExtras.fromJson({
      'actual_cash_amount': 45,
      'distance_review': {
        'actual_km': 1.5,
        'booked_km': 6,
        'flagged_at': '2026-10-19T10:00:00Z',
        'source': 'complete_job',
      },
    });
    expect(x.actualCashAmount, 45.0);
    expect(x.distanceReview?.actualKm, 1.5);
    expect(x.distanceReview?.bookedKm, 6.0);
    expect(x.distanceReview?.source, 'complete_job');
    expect(OwnerJobExtras.fromJson(null).distanceReview, isNull);
    expect(OwnerJobExtras.fromJson({'distance_review': 'x'}).distanceReview,
        isNull);
  });

  test('employee parsing; kye_status only when present', () {
    final list = OwnerEmployee.listFrom([
      {
        'id': 'e1',
        'username': ' ',
        'email': 'a@b.io',
        'is_active': true,
        'created_at': '2026-10-01T00:00:00Z',
      },
      {'id': 'e2', 'username': 'Mo', 'kye_status': 'approved'},
      'junk',
    ]);
    expect(list.length, 2);
    expect(list[0].displayName, 'a@b.io');
    expect(list[0].kyeStatus, isNull);
    expect(list[0].createdAt, isNotNull);
    expect(list[1].isActive, isFalse);
    expect(list[1].kyeStatus, 'approved');
  });

  group('toggleFailureOf', () {
    for (final (err, kind) in [
      (
        ApiClientException('invalid owner credentials', statusCode: 403),
        ToggleFailure.wrongPassword
      ),
      (
        ApiClientException('action blocked: owner KYC approval is pending',
            statusCode: 403),
        ToggleFailure.kybNotApproved
      ),
      (
        ApiClientException('upgrade_required', statusCode: 402),
        ToggleFailure.paidPlanRequired
      ),
      (
        ApiClientException('failed to freeze', statusCode: 503),
        ToggleFailure.unavailable
      ),
      (
        ApiClientException('slow down', statusCode: 429),
        ToggleFailure.tooManyTries
      ),
      (
        ApiClientException('employee not found', statusCode: 400),
        ToggleFailure.other
      ),
    ]) {
      test('${err.statusCode} ${err.message} -> $kind', () {
        expect(toggleFailureOf(err), kind);
      });
    }
    test('non-API error', () {
      expect(toggleFailureOf(StateError('x')), ToggleFailure.other);
    });
  });

  test('conflict = 409 only', () {
    expect(isConflict(ApiClientException('expired', statusCode: 409)), isTrue);
    expect(isConflict(ApiClientException('bad', statusCode: 400)), isFalse);
    expect(isConflict(Exception('x')), isFalse);
  });

  test('username and email rules match the old employee screen', () {
    expect(usernameProblem(''), UsernameProblem.required);
    expect(usernameProblem('ab'), UsernameProblem.tooShort);
    expect(usernameProblem('a' * 31), UsernameProblem.tooLong);
    expect(usernameProblem('karim!'), UsernameProblem.invalidChars);
    expect(usernameProblem('كريم_1'), isNull);
    expect(isValidEmail('k@x.io'), isTrue);
    expect(isValidEmail('k@x'), isFalse);
  });

  test('team filter', () {
    expect(teamFilterMatches(TeamFilter.all, _frozen), isTrue);
    expect(teamFilterMatches(TeamFilter.active, _frozen), isFalse);
    expect(teamFilterMatches(TeamFilter.frozen, _frozen), isTrue);
  });
}
