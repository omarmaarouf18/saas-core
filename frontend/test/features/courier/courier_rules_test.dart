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
}
