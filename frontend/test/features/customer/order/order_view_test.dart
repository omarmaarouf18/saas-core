import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/order/order_view.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';

void main() {
  final now = fixedNow;

  group('orderViewFor', () {
    const cases = {
      'pending': OrderViewKind.searching,
      'pending_dispatch': OrderViewKind.searching,
      'unavailable': OrderViewKind.unavailable,
      'awaiting_price_response': OrderViewKind.priceProposal,
      'assigned': OrderViewKind.active,
      'active': OrderViewKind.active,
      'escrow_reconciliation_required': OrderViewKind.underReview,
      'reconciliation_required': OrderViewKind.underReview,
      'completed': OrderViewKind.completed,
      'cancelled': OrderViewKind.cancelled,
      'canceled': OrderViewKind.cancelled,
    };
    cases.forEach((status, view) {
      test('$status -> ${view.name}', () {
        expect(orderViewFor(orderJob(status: status), now), view);
      });
    });

    test('ignores case and surrounding space', () {
      expect(orderViewFor(orderJob(status: '  ACTIVE '), now),
          OrderViewKind.active);
      expect(orderViewFor(orderJob(status: 'Pending_Dispatch'), now),
          OrderViewKind.searching);
    });

    test('unknown, empty and future statuses -> unknown', () {
      for (final s in ['', '   ', 'picked_up', 'refunded', 'weird']) {
        expect(orderViewFor(orderJob(status: s), now), OrderViewKind.unknown,
            reason: s);
      }
    });

    test('awaiting price with a live window -> priceProposal', () {
      final job = orderJob(
        status: 'awaiting_price_response',
        proposed: 50,
        proposedBy: 'employee',
        proposalExpiresAt: now.add(const Duration(seconds: 1)),
      );
      expect(orderViewFor(job, now), OrderViewKind.priceProposal);
    });

    test('awaiting price without an expiry -> priceProposal', () {
      expect(orderViewFor(orderJob(status: 'awaiting_price_response'), now),
          OrderViewKind.priceProposal);
    });

    test('awaiting price at or past its expiry -> cancelled', () {
      for (final exp in [now, now.subtract(const Duration(seconds: 1))]) {
        final job =
            orderJob(status: 'awaiting_price_response', proposalExpiresAt: exp);
        expect(orderViewFor(job, now), OrderViewKind.cancelled);
        expect(isProposalExpired(job, now), isTrue);
      }
    });

    test('the expiry only matters while awaiting a price', () {
      final job = orderJob(
          status: 'active',
          proposalExpiresAt: now.subtract(const Duration(minutes: 1)));
      expect(orderViewFor(job, now), OrderViewKind.active);
      expect(isProposalExpired(job, now), isFalse);
    });

    test('cancellation fields do not change the view', () {
      // A pending employee cancellation request is a chip, not a view.
      expect(
          orderViewFor(
              orderJob(status: 'active', cancellationRequestStatus: 'pending'),
              now),
          OrderViewKind.active);
      // A reason on a non-cancelled job is ignored.
      expect(
          orderViewFor(
              orderJob(status: 'completed', cancellationReason: 'late'), now),
          OrderViewKind.completed);
    });

    test('is pure: same input, same output', () {
      final job = orderJob(status: 'awaiting_price_response');
      expect(orderViewFor(job, now), orderViewFor(job, now));
    });
  });

  group('isProposalExpired', () {
    test('server reason price_proposal_expired', () {
      expect(
          isProposalExpired(
              orderJob(
                  status: 'cancelled',
                  cancellationReason: 'price_proposal_expired'),
              now),
          isTrue);
    });

    test('other cancellations are not expiries', () {
      expect(
          isProposalExpired(
              orderJob(status: 'cancelled', cancellationReason: 'changed mind'),
              now),
          isFalse);
      expect(isProposalExpired(orderJob(status: 'cancelled'), now), isFalse);
    });
  });

  group('rules', () {
    test('customer may cancel only while searching', () {
      for (final s in ['pending', 'pending_dispatch']) {
        expect(canCustomerCancel(orderJob(status: s)), isTrue, reason: s);
      }
      for (final s in [
        'unavailable',
        'awaiting_price_response',
        'active',
        'completed',
        'cancelled',
        'escrow_reconciliation_required',
        'weird',
      ]) {
        expect(canCustomerCancel(orderJob(status: s)), isFalse, reason: s);
      }
    });

    test('polling stops only on finished jobs', () {
      for (final s in ['completed', 'cancelled', 'canceled', 'unavailable']) {
        expect(shouldPoll(orderJob(status: s)), isFalse, reason: s);
      }
      for (final s in [
        'pending',
        'pending_dispatch',
        'awaiting_price_response',
        'active',
        'escrow_reconciliation_required',
        'weird',
      ]) {
        expect(shouldPoll(orderJob(status: s)), isTrue, reason: s);
      }
    });

    test('proposal party', () {
      expect(proposalParty(orderJob()), ProposalParty.none);
      expect(proposalParty(orderJob(proposed: 40, proposedBy: 'customer')),
          ProposalParty.customer);
      expect(proposalParty(orderJob(proposed: 40, proposedBy: 'employee')),
          ProposalParty.courier);
      expect(proposalParty(orderJob(proposed: 40, proposedBy: 'owner')),
          ProposalParty.courier);
    });

    test('counter-offer bounds are 0.5x to 1.5x, inclusive', () {
      expect(counterOfferBounds(40), (min: 20.0, max: 60.0));
      expect(validateCounterOffer('20', 40), isNull);
      expect(validateCounterOffer(' 60 ', 40), isNull);
      expect(validateCounterOffer('19.99', 40), CounterOfferError.outOfRange);
      expect(validateCounterOffer('60.01', 40), CounterOfferError.outOfRange);
      expect(validateCounterOffer('abc', 40), CounterOfferError.notANumber);
      expect(validateCounterOffer('', 40), CounterOfferError.notANumber);
    });
  });
}
