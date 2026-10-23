import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/courier_rules.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';

Job _job(String id, String status,
        {DateTime? offerExpiresAt, DateTime? updatedAt}) =>
    Job(
      id: id,
      ownerId: 'o',
      userId: 'u',
      serviceId: 's',
      status: status,
      location: JobLocation(latitude: 30, longitude: 31),
      paymentMethod: 'cod',
      offerExpiresAt: offerExpiresAt,
      updatedAt: updatedAt,
    );

UserProfile _courier({String? kye, String? account, String? reason}) =>
    UserProfile(
      id: 'emp-1',
      email: 'c@example.com',
      username: 'Karim',
      role: 'employee',
      kyeStatus: kye,
      accountStatus: account,
      suspensionReason: reason,
    );

void main() {
  final now = DateTime(2026, 10, 19, 15, 30);

  group('job buckets', () {
    test('offer, current and finished', () {
      expect(isOffer(_job('1', ' Pending_Dispatch ')), isTrue);
      for (final s in ['active', 'awaiting_price_response', 'pending', 'x']) {
        expect(isCurrent(_job('1', s)), isTrue, reason: s);
      }
      for (final s in [
        'completed',
        'cancelled',
        'unavailable',
        'escrow_reconciliation_required',
      ]) {
        expect(isCourierFinished(_job('1', s)), isTrue, reason: s);
        expect(isCurrent(_job('1', s)), isFalse, reason: s);
      }
      expect(isCurrent(_job('1', 'pending_dispatch')), isFalse);
    });

    test('currentOffer picks the one that expires first', () {
      final jobs = [
        _job('late', 'pending_dispatch',
            offerExpiresAt: now.add(const Duration(seconds: 50))),
        _job('none', 'pending_dispatch'),
        _job('soon', 'pending_dispatch',
            offerExpiresAt: now.add(const Duration(seconds: 10))),
        _job('a', 'active'),
      ];
      expect(currentOffer(jobs)!.id, 'soon');
      expect(currentOffer([_job('a', 'active')]), isNull);
    });

    test('isOfferExpired at and after the expiry, or without one', () {
      final j = _job('1', 'pending_dispatch', offerExpiresAt: now);
      expect(isOfferExpired(j, now), isTrue);
      expect(
          isOfferExpired(j, now.subtract(const Duration(seconds: 1))), isFalse);
      expect(isOfferExpired(_job('2', 'pending_dispatch'), now), isTrue);
    });

    test('currentJob prefers active, then awaiting price, newest first', () {
      final jobs = [
        _job('pend', 'pending', updatedAt: now),
        _job('price', 'awaiting_price_response', updatedAt: now),
        _job('old', 'active',
            updatedAt: now.subtract(const Duration(hours: 1))),
        _job('new', 'active', updatedAt: now),
        _job('done', 'completed', updatedAt: now),
      ];
      expect(currentJob(jobs)!.id, 'new');
      expect(otherCurrentCount(jobs), 3);
      expect(currentJob(jobs.where((j) => j.status != 'active'))!.id, 'price');
      expect(currentJob([_job('done', 'completed')]), isNull);
      expect(otherCurrentCount([_job('a', 'active')]), 0);
    });

    test('availability is locked only by an active job', () {
      expect(hasActiveJob([_job('1', 'awaiting_price_response')]), isFalse);
      expect(hasActiveJob([_job('1', 'active')]), isTrue);
    });
  });

  group('account', () {
    test('KYE state from kye_status', () {
      expect(kyeStateOf(_courier(kye: 'approved')), KyeState.approved);
      expect(kyeStateOf(_courier(kye: 'rejected')), KyeState.rejected);
      expect(kyeStateOf(_courier()), KyeState.missing);
      expect(kyeStateOf(_courier(kye: '')), KyeState.missing);
      expect(kyeStateOf(_courier(kye: 'pending_super_admin_approval')),
          KyeState.pending);
      expect(kyeStateOf(null), KyeState.missing);
    });

    test('blocked when the account is suspended (or frozen)', () {
      expect(isBlocked(_courier(account: 'suspended')), isTrue);
      expect(isBlocked(_courier(account: 'active')), isFalse);
      expect(isBlocked(_courier()), isFalse);
      expect(isBlocked(null), isFalse);
    });
  });

  group('my jobs', () {
    JobStatusHistoryEntry at(String status, DateTime t) =>
        JobStatusHistoryEntry(status: status, at: t);
    Job done(String id,
            {String status = 'completed',
            DateTime? finished,
            DateTime? created,
            double? price = 40,
            String payment = 'cod'}) =>
        Job(
          id: id,
          ownerId: 'o',
          userId: 'u',
          serviceId: 's',
          status: status,
          location: JobLocation(latitude: 30, longitude: 31),
          paymentMethod: payment,
          suggestedPrice: price,
          createdAt: created ?? now.subtract(const Duration(days: 3)),
          statusHistory: finished == null ? const [] : [at(status, finished)],
        );

    test('today counts by completion time, cash at order price', () {
      final s = todayStats([
        done('a', finished: now.subtract(const Duration(hours: 2))),
        done('b', finished: now.subtract(const Duration(hours: 1)), price: 25),
        // Finished yesterday although created today: not counted.
        done('c',
            finished: now.subtract(const Duration(days: 1)), created: now),
        // Not cash: counted, no cash.
        done('d',
            finished: now.subtract(const Duration(minutes: 5)),
            payment: 'wallet'),
        done('e', status: 'cancelled', finished: now),
      ], now);
      expect(s.completed, 3);
      expect(s.cash, 65);
      expect(s.estimated, isFalse);
    });

    test('older jobs without a timeline count by creation day', () {
      final s = todayStats([
        done('old', created: now.subtract(const Duration(hours: 3))),
        done('older', created: now.subtract(const Duration(days: 2))),
      ], now);
      expect(s.completed, 1);
      expect(s.cash, 40);
      expect(s.estimated, isTrue);
    });

    test('finished list: newest end first, running jobs left out', () {
      final list = finishedJobs([
        done('mid', finished: now.subtract(const Duration(hours: 2))),
        _job('run', 'active'),
        done('new', status: 'cancelled', finished: now),
        done('review',
            status: 'escrow_reconciliation_required',
            finished: now.subtract(const Duration(hours: 5))),
      ]);
      expect(list.map((j) => j.id), ['new', 'mid', 'review']);
      expect(finishedAt(list.first), now);
      expect(finishedAt(_job('x', 'completed')), isNull);
    });
  });

  group('current job action', () {
    Job active(String? sub, {String status = 'active'}) => Job(
          id: 'j',
          ownerId: 'o',
          userId: 'u',
          serviceId: 's',
          status: status,
          subStatus: sub,
          location: JobLocation(latitude: 1, longitude: 2),
          destination: JobLocation(latitude: 3, longitude: 4),
          paymentMethod: 'cod',
        );

    test('pickup, then deliver; older jobs deliver', () {
      expect(
          primaryActionFor(active('heading_to_pickup')), CourierAction.pickup);
      expect(primaryActionFor(active('picked_up')), CourierAction.deliver);
      expect(primaryActionFor(active(null)), CourierAction.deliver);
      expect(primaryActionFor(active(null, status: 'awaiting_price_response')),
          CourierAction.none);
      expect(navigationTarget(active('heading_to_pickup')).latitude, 1);
      expect(navigationTarget(active('picked_up')).latitude, 3);
    });

    test('cancellation can be requested unless one is pending', () {
      expect(canRequestCancellation(active('picked_up')), isTrue);
      expect(canRequestCancellation(_job('1', 'completed')), isFalse);
    });
  });
}
