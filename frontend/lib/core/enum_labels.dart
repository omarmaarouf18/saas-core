import '../l10n/app_localizations.dart';

/// Localized labels for backend enum codes (B1), following the
/// `audit_labels.dart` pattern: one mapping per enum family (EN +
/// Egyptian Arabic ARB keys) with a humanized fallback for unknown values
/// — never the raw uppercase code.
///
/// Truncated IDs are NOT covered here: they are a sanctioned convention
/// (DESIGN_SYSTEM 2.7) and stay as-is.
String humanizeMachineCode(String code) {
  final words = code
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  words[0] = words[0][0].toUpperCase() + words[0].substring(1);
  return words.join(' ');
}

/// Backend `payment_method`: cod, wallet.
String paymentMethodLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'cod':
      return l10n.codOptionTitle;
    case 'wallet':
      return l10n.enumPaymentWallet;
    default:
      return _fallback(l10n, code);
  }
}

/// Backend user `role`: owner, employee, user.
String userRoleLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'owner':
      return l10n.roleOwnerLabel;
    case 'employee':
      return l10n.roleEmployeeLabel;
    case 'user':
      return l10n.enumRoleUser;
    default:
      return _fallback(l10n, code);
  }
}

/// Backend subscription tier: free, paid, pending_payment, cancelled.
String subscriptionTierLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'free':
      return l10n.enumTierFree;
    case 'paid':
      return l10n.enumTierPaid;
    case 'pending_payment':
      return l10n.enumTierPendingPayment;
    case 'cancelled':
    case 'canceled':
      return l10n.statusCancelled;
    default:
      return _fallback(l10n, code);
  }
}

/// Backend `payout_method`: bank_transfer, instapay, vodafone_cash.
String payoutMethodLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'bank_transfer':
      return l10n.payoutMethodBankTransfer;
    case 'instapay':
      return l10n.payoutMethodInstapay;
    case 'vodafone_cash':
      return l10n.enumPayoutVodafoneCash;
    default:
      return _fallback(l10n, code);
  }
}

/// Backend ledger `type`: deposit, escrow_lock, escrow_release,
/// platform_fee, payout, payout_refund (+ legacy refund/fee_deduction).
String transactionTypeLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'deposit':
      return l10n.enumTxnDeposit;
    case 'escrow_lock':
      return l10n.enumTxnEscrowLock;
    case 'escrow_release':
      return l10n.enumTxnEscrowRelease;
    case 'platform_fee':
      return l10n.enumTxnPlatformFee;
    case 'payout':
      return l10n.enumTxnPayout;
    case 'payout_refund':
      return l10n.enumTxnPayoutRefund;
    case 'refund':
      return l10n.enumTxnRefund;
    case 'fee_deduction':
      return l10n.enumTxnFeeDeduction;
    default:
      return _fallback(l10n, code);
  }
}

/// Backend escrow failure reason: under_distance_mismatch,
/// escrow_amount_unrecorded, implausible_speed. Unknown reasons humanize
/// (fixes sweep S1 the same way F1 fixed audit codes).
String escrowFailureReasonLabel(AppLocalizations l10n, String code) {
  switch (code.trim()) {
    case 'under_distance_mismatch':
      return l10n.reconciliationUnderDistance;
    case 'escrow_amount_unrecorded':
      return l10n.reconciliationUnrecordedEscrow;
    case 'implausible_speed':
      return l10n.reconciliationImplausibleSpeed;
    default:
      if (code.trim().isEmpty) return l10n.reconciliationRequiredDefault;
      return humanizeMachineCode(code);
  }
}

/// Backend job `status` for non-badge text slots. Badge rendering stays on
/// StatusBadge (which maps the same `status*` keys); this covers inline
/// text such as the employee card time line.
String jobStatusLabel(AppLocalizations l10n, String code) {
  switch (code.trim().toLowerCase()) {
    case 'pending':
      return l10n.statusPending;
    case 'pending_dispatch':
      return l10n.statusPendingDispatch;
    case 'unavailable':
      return l10n.statusUnavailable;
    case 'awaiting_price_response':
      return l10n.statusAwaitingPrice;
    case 'active':
      return l10n.statusActive;
    case 'completed':
      return l10n.statusCompleted;
    case 'cancelled':
    case 'canceled':
      return l10n.statusCancelled;
    case 'escrow_reconciliation_required':
    case 'reconciliation_required':
      return l10n.statusReconciliationRequired;
    default:
      return _fallback(l10n, code);
  }
}

String _fallback(AppLocalizations l10n, String code) {
  if (code.trim().isEmpty) return l10n.statusUnknown;
  final humanized = humanizeMachineCode(code);
  return humanized.isEmpty ? l10n.statusUnknown : humanized;
}
