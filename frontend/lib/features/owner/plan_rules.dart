/// Rules for the read-only plan and wallet pages (FE-OWNER-2b).
library;

import '../../l10n/app_localizations.dart';
import '../../ui/qd_ui.dart';

/// `GET /users/subscription` tiers (user-service models.PlanTier).
enum PlanTier { free, paid, pending, cancelled, unknown }

PlanTier planTierOf(String? raw) => switch (raw?.trim().toLowerCase()) {
      'free' || '' || null => PlanTier.free,
      'paid' => PlanTier.paid,
      'pending_payment' => PlanTier.pending,
      'cancelled' || 'canceled' => PlanTier.cancelled,
      _ => PlanTier.unknown,
    };

String planLabel(AppLocalizations l10n, String? raw) =>
    switch (planTierOf(raw)) {
      PlanTier.free => l10n.ownPlanFree,
      PlanTier.paid => l10n.ownPlanPaid,
      PlanTier.pending => l10n.ownPlanPending,
      PlanTier.cancelled => l10n.ownPlanCancelled,
      PlanTier.unknown => l10n.ownPlanUnknown,
    };

/// What customers see (ADR-0024 `Subscription.IsClosed`): a business is
/// open only on the paid tier and before a set expiry; otherwise it is left
/// out of the services list and bookings are refused.
enum PlanAccess { open, openUntil, expired, closed }

PlanAccess planAccessOf(String? tier, DateTime? expiresAt, DateTime now) {
  if (planTierOf(tier) != PlanTier.paid) return PlanAccess.closed;
  if (expiresAt == null) return PlanAccess.open;
  return now.isAfter(expiresAt) ? PlanAccess.expired : PlanAccess.openUntil;
}

/// Payout request statuses (user-service models.PayoutStatus).
(String, QdTone) payoutStatusChip(AppLocalizations l10n, String status) =>
    switch (status.trim().toLowerCase()) {
      'requested' => (l10n.ownPayoutRequested, QdTone.warning),
      'approved' => (l10n.ownPayoutApproved, QdTone.success),
      'paid' => (l10n.ownPayoutPaid, QdTone.success),
      'rejected' => (l10n.ownPayoutRejected, QdTone.danger),
      _ => (l10n.ownPayoutUnknown, QdTone.neutral),
    };
