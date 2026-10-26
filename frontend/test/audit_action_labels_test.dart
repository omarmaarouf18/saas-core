import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/audit_labels.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';

/// F1: the owner audit trail shows friendly localized labels, never the raw
/// backend action code, and never the client IP.
void main() {
  group('auditActionLabel mapping (EN)', () {
    final l10n = AppLocalizationsEn();

    test('known machine codes map to friendly labels', () {
      expect(auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'), 'Account suspended');
      expect(
          auditActionLabel(l10n, 'ACCOUNT_REACTIVATED'), 'Account reactivated');
      expect(
          auditActionLabel(l10n, 'KYC_REVIEWED'), 'Identity review completed');
      expect(auditActionLabel(l10n, 'DOCUMENT_VIEWED'), 'Document viewed');
    });

    test('unknown codes fall back to humanized sentence case, never raw', () {
      expect(auditActionLabel(l10n, 'SOME_NEW_EVENT'), 'Some new event');
      expect(auditActionLabel(l10n, 'BOOKING_ATTEMPT_CLOSED_BUSINESS'),
          'Booking attempt closed business');
      // The fallback is never the identity function on the raw code.
      expect(
          humanizeAuditAction('SOME_NEW_EVENT') == 'SOME_NEW_EVENT', isFalse);
    });

    test('free-form employee-typed actions pass through untouched', () {
      expect(auditActionLabel(l10n, 'Arrived at Pickup'), 'Arrived at Pickup');
    });

    test('empty action falls back to the unknown-action label', () {
      expect(auditActionLabel(l10n, ''), l10n.unknownActionLabel);
      expect(auditActionLabel(l10n, '   '), l10n.unknownActionLabel);
    });
  });

  group('auditActionLabel mapping (AR)', () {
    final l10n = AppLocalizationsAr();

    test('known machine codes map to Egyptian Arabic labels without parens',
        () {
      expect(auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'), 'تم تجميد الحساب');
      expect(auditActionLabel(l10n, 'KYC_REVIEWED'), 'مراجعة الهوية اكتملت');
      for (final label in [
        auditActionLabel(l10n, 'ACCOUNT_SUSPENDED'),
        auditActionLabel(l10n, 'ACCOUNT_REACTIVATED'),
        auditActionLabel(l10n, 'KYC_REVIEWED'),
        auditActionLabel(l10n, 'DOCUMENT_VIEWED'),
      ]) {
        expect(label.contains('('), isFalse);
        expect(label.contains(')'), isFalse);
      }
    });
  });

  group('humanizeAuditAction fallback', () {
    test('underscores become spaces with sentence case', () {
      expect(humanizeAuditAction('ACCOUNT_SUSPENDED'), 'Account suspended');
      expect(humanizeAuditAction('A_B_C'), 'A b c');
    });

    test('already-lowercase input is sentence-cased, never uppercased', () {
      expect(humanizeAuditAction('arrived at pickup'), 'Arrived at pickup');
    });
  });
}
