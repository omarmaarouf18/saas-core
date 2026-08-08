# ADR-0017: Zero-Commission Subscription-Only Revenue Model

- **Status**: Proposed
- **Date**: 2026-08-08
- **Related Commit SHA**: Uncommitted / Pending Implementation
- **Related Audit Finding**: `docs/BUSINESS_LOGIC_AUDIT.md` (Finding 1 & Finding 2)

## Context

A recent business-logic audit (`docs/BUSINESS_LOGIC_AUDIT.md`) found that the current codebase deducts a 15% platform fee (`PlatformFeePercentage`, currently defaulting to `15.0` in the `platform_config` collection) on every completed job, via `ReleaseEscrowWithSplit` (electronic/wallet-based payments) and `DeductCODFee` (cash-on-delivery payments), in `services/user-service/internal/store/mongodb.go`.

This does not reflect the actual, current business model: the platform's only revenue source is the monthly SaaS subscription fee, which already covers infrastructure, the application, and the payment gateway the platform provides. The platform takes 0% of any transaction, regardless of payment method — all transaction value belongs entirely to the owner.

## Decision

1. **0% Platform Commission**: Platform commission is set to 0% across all payment methods. The `PlatformFeePercentage` concept is removed/zeroed, not merely lowered — the fee-splitting mechanism itself no longer applies.
2. **Cash-on-Delivery (COD) Zero Financial Mutation**: Cash-on-Delivery (COD) payments involve NO money movement within the platform's financial system at all. The employee physically holds the cash; the platform's role is purely to log that collection occurred (amount, job, timestamp) for record-keeping. No wallet balance, escrow, or ledger entry should be created or modified for a COD collection event — `CompleteJob`'s COD path must stop calling any wallet-balance-mutating function for this case.
3. **Electronic Payment Centralized Credits & Payout Model**: Electronic payments (Visa/InstaPay, or any future gateway) DO flow through the platform's payment gateway, so real settled funds are held centrally by the platform before reaching the owner. This requires a centralized "credits" model: 100% of the amount paid electronically is credited to the owner's balance (no fee deduction), and the owner can later request a payout/withdrawal of their accumulated balance to their own bank account or payment method — this mirrors how Uber and similar marketplace platforms centralize card payment collection and let drivers withdraw earnings on demand, rather than requiring every individual owner to have their own payment gateway account (confirmed infeasible per business decision).
4. **New Owner Withdrawal/Payout Request Capability**: A NEW withdrawal/payout capability must be built — currently, `withdrawable_balance` exists as a stored field but there is no endpoint or workflow for an owner to actually request a payout. This is new functionality, not a modification of existing functionality. Payout fulfillment mechanics (manual bank transfer processing, InstaPay send, etc.) are explicitly OUT OF SCOPE for this ADR — this ADR only establishes that the request/tracking capability must exist; the fulfillment/settlement process is a separate operational and possibly future-code decision.

## Consequences

- `ReleaseEscrowWithSplit`, `DeductCODFee`, and the `platform_wallet_id` / platform-central wallet concept as currently implemented no longer match intended behavior and require rework in a follow-up implementation task (do not implement in this ADR task).
- The existing escrow LOCKING mechanism for electronic payments (job's `locked_escrow_amount`, held until job completion) is NOT necessarily removed — it may still be the correct mechanism for holding electronic payment funds until job completion for dispute-resolution purposes, just with 0% fee taken on release rather than a 15%/85% split. Flag this as an open question for the follow-up implementation task to confirm rather than deciding definitively here.
- All existing wallet/ledger financial tests referencing `PlatformFeePercentage` or fee amounts will need rework in the follow-up implementation task.
- Existing production data (`platform_config` document with `PlatformFeePercentage: 15.0`) will need a data correction once code changes land — note this as a required step for the follow-up task, not something to execute now.

## Alternatives Considered

- **Per-owner individual payment gateway accounts**: Rejected as infeasible; most owners would not have or want to set up their own merchant/gateway accounts.
- **Keeping a small percentage fee alongside the subscription**: Rejected; business decision is that subscription revenue alone covers platform costs, and a dual-revenue model (subscription + commission) is not the intended pricing strategy.
