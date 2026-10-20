import '../../../core/job_rules.dart';
import '../../../models/job.dart';

/// The one state view the order detail page renders (FE-CUST-2).
enum OrderViewKind {
  /// pending, pending_dispatch: the job is offered to couriers (A-Searching).
  searching,

  /// unavailable: every courier declined or timed out; retry booking.
  unavailable,

  /// awaiting_price_response with a live proposal window (A-Negotiate).
  priceProposal,

  /// active (and the client-side alias assigned): a courier works on it
  /// (A-Track).
  active,

  /// escrow_reconciliation_required / reconciliation_required.
  underReview,

  /// completed (A-Rate entry point).
  completed,

  /// cancelled / canceled, and a price proposal whose window has passed.
  cancelled,

  /// Any status this client does not know: summary only, no actions.
  unknown,
}

/// The server's price proposal window (user-service: 5 minutes after the
/// proposal). Only used to size the countdown bar.
const Duration kPriceProposalWindow = Duration(minutes: 5);

String _norm(String? status) => status?.trim().toLowerCase() ?? '';

/// Picks the single view for [job] at [now]. Pure: same input, same view.
///
/// An awaiting-price job whose `price_proposal_expires_at` is not after
/// [now] is shown as cancelled right away: the server cancels it with
/// `price_proposal_expired`, and the next poll confirms it.
OrderViewKind orderViewFor(Job job, DateTime now) {
  switch (_norm(job.status)) {
    case 'pending':
    case 'pending_dispatch':
      return OrderViewKind.searching;
    case 'unavailable':
      return OrderViewKind.unavailable;
    case 'awaiting_price_response':
      return isProposalWindowOver(job, now)
          ? OrderViewKind.cancelled
          : OrderViewKind.priceProposal;
    case 'assigned':
    case 'active':
      return OrderViewKind.active;
    case 'escrow_reconciliation_required':
    case 'reconciliation_required':
      return OrderViewKind.underReview;
    case 'completed':
      return OrderViewKind.completed;
    case 'cancelled':
    case 'canceled':
      return OrderViewKind.cancelled;
    default:
      return OrderViewKind.unknown;
  }
}

/// Whether the price proposal window of [job] has passed at [now] (false
/// when the job carries no expiry).
bool isProposalWindowOver(Job job, DateTime now) {
  final expires = job.priceProposalExpiresAt;
  return expires != null && !expires.isAfter(now);
}

/// Whether [job] ended because nobody answered a price proposal in time:
/// the server's `price_proposal_expired` reason, or an awaiting-price job
/// past its window that the server has not cancelled yet.
bool isProposalExpired(Job job, DateTime now) =>
    job.cancellationReason?.trim() == 'price_proposal_expired' ||
    (_norm(job.status) == 'awaiting_price_response' &&
        isProposalWindowOver(job, now));

/// Statuses the customer may cancel from the order page: the same rule as
/// the old JobStatusScreen (still looking for a courier).
bool canCustomerCancel(Job job) {
  final s = _norm(job.status);
  return s == 'pending' || s == 'pending_dispatch';
}

/// Whether the page keeps polling for [job]: until it is finished
/// (core/job_rules.dart). Unknown statuses keep polling too, so a status
/// this client does not know can still move on to one it does.
bool shouldPoll(Job job) => !isFinished(job);

/// Who made the open price proposal, from the customer's point of view.
enum ProposalParty { none, customer, courier }

ProposalParty proposalParty(Job job) {
  if (job.proposedPrice == null) return ProposalParty.none;
  return job.proposedBy?.trim().toLowerCase() == 'customer'
      ? ProposalParty.customer
      : ProposalParty.courier;
}

/// Counter-offer bounds, the same as the old screen and the server
/// (models.ValidPriceProposal): 0.5× to 1.5× the suggested price.
({double min, double max}) counterOfferBounds(double suggested) =>
    (min: 0.5 * suggested, max: 1.5 * suggested);

/// Why a counter-offer input is rejected before it is sent, or null when
/// it may be sent.
enum CounterOfferError { notANumber, outOfRange }

CounterOfferError? validateCounterOffer(String input, double suggested) {
  final value = double.tryParse(input.trim());
  if (value == null) return CounterOfferError.notANumber;
  final b = counterOfferBounds(suggested);
  const eps = 1e-9;
  if (value < b.min - eps || value > b.max + eps) {
    return CounterOfferError.outOfRange;
  }
  return null;
}
