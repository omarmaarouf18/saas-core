import '../l10n/app_localizations.dart';

/// Human-readable labels for backend audit action codes.
///
/// The audit-log endpoint returns machine codes (`ACCOUNT_SUSPENDED`,
/// `KYC_REVIEWED`, ...) plus free-form employee-typed actions
/// ("Arrived at Pickup"). Screens must never render the raw uppercase code:
/// known codes map to localized labels below, everything else falls back to
/// [humanizeAuditAction], which sentence-cases the code instead of shouting
/// it in uppercase.
String auditActionLabel(AppLocalizations l10n, String rawAction) {
  switch (rawAction.trim()) {
    case 'ACCOUNT_SUSPENDED':
      return l10n.auditActionAccountSuspended;
    case 'ACCOUNT_REACTIVATED':
      return l10n.auditActionAccountReactivated;
    case 'KYC_REVIEWED':
      return l10n.auditActionKycReviewed;
    case 'DOCUMENT_VIEWED':
      return l10n.auditActionDocumentViewed;
    default:
      final trimmed = rawAction.trim();
      if (trimmed.isEmpty) return l10n.unknownActionLabel;
      // Free-form employee-typed actions are already human prose — pass
      // through untouched. Only machine codes (underscores / all-caps)
      // get humanized.
      if (trimmed.contains('_') || trimmed == trimmed.toUpperCase()) {
        return humanizeAuditAction(trimmed);
      }
      return trimmed;
  }
}

/// Fallback for unknown machine codes: `SOME_NEW_EVENT` becomes
/// `Some new event`. Never returns the raw uppercase code.
String humanizeAuditAction(String action) {
  final words = action
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
