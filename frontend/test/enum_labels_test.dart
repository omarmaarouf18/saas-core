import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/enum_labels.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';

/// B1: one localized mapping per enum family with a humanized fallback.
/// Unknown codes sentence-case; empty codes use the unknown label; raw
/// uppercase codes never surface.
void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  group('paymentMethodLabel', () {
    test('EN known values', () {
      expect(paymentMethodLabel(en, 'cod'), 'Cash on delivery');
      expect(paymentMethodLabel(en, 'wallet'), 'Wallet');
      expect(paymentMethodLabel(en, 'COD'), 'Cash on delivery');
    });
    test('AR known values', () {
      expect(paymentMethodLabel(ar, 'cod'), 'الدفع عند الاستلام كاش');
      expect(paymentMethodLabel(ar, 'wallet'), 'المحفظة');
    });
    test('unknown falls back humanized', () {
      expect(paymentMethodLabel(en, 'bank_card'), 'Bank card');
      expect(paymentMethodLabel(en, ''), en.statusUnknown);
    });
  });

  group('userRoleLabel', () {
    test('EN/AR known values', () {
      expect(userRoleLabel(en, 'owner'), 'Owner');
      expect(userRoleLabel(en, 'employee'), 'Employee');
      expect(userRoleLabel(en, 'user'), 'User');
      expect(userRoleLabel(ar, 'owner'), 'صاحب الحساب');
      expect(userRoleLabel(ar, 'employee'), 'موظف');
      expect(userRoleLabel(ar, 'user'), 'مستخدم');
    });
    test('unknown falls back humanized', () {
      expect(userRoleLabel(en, 'super_admin'), 'Super admin');
    });
  });

  group('subscriptionTierLabel', () {
    test('EN/AR known values', () {
      expect(subscriptionTierLabel(en, 'free'), 'Free');
      expect(subscriptionTierLabel(en, 'paid'), 'Paid');
      expect(subscriptionTierLabel(en, 'pending_payment'), 'Pending payment');
      expect(subscriptionTierLabel(en, 'cancelled'), 'Cancelled');
      expect(subscriptionTierLabel(ar, 'pending_payment'), 'دفع معلق');
    });
    test('unknown falls back humanized', () {
      expect(subscriptionTierLabel(en, 'trial_30'), 'Trial 30');
    });
  });

  group('payoutMethodLabel', () {
    test('EN/AR known values', () {
      expect(payoutMethodLabel(en, 'bank_transfer'), 'Bank Transfer');
      expect(payoutMethodLabel(en, 'instapay'), 'InstaPay');
      expect(payoutMethodLabel(en, 'vodafone_cash'), 'Vodafone Cash');
      expect(payoutMethodLabel(ar, 'vodafone_cash'), 'فودافون كاش');
    });
    test('unknown falls back humanized', () {
      expect(payoutMethodLabel(en, 'western_union'), 'Western union');
    });
  });

  group('transactionTypeLabel', () {
    test('EN/AR known values', () {
      expect(transactionTypeLabel(en, 'deposit'), 'Deposit');
      expect(transactionTypeLabel(en, 'escrow_lock'), 'Escrow lock');
      expect(transactionTypeLabel(en, 'escrow_release'), 'Escrow release');
      expect(transactionTypeLabel(en, 'platform_fee'), 'Platform fee');
      expect(transactionTypeLabel(en, 'payout'), 'Payout');
      expect(transactionTypeLabel(en, 'payout_refund'), 'Payout refund');
      expect(transactionTypeLabel(ar, 'deposit'), 'إيداع');
      expect(transactionTypeLabel(ar, 'payout'), 'سحب أرباح');
    });
    test('unknown falls back humanized', () {
      expect(transactionTypeLabel(en, 'mystery_type'), 'Mystery type');
    });
  });

  group('escrowFailureReasonLabel', () {
    test('known reasons reuse reconciliation copy', () {
      expect(escrowFailureReasonLabel(en, 'under_distance_mismatch'),
          en.reconciliationUnderDistance);
      expect(escrowFailureReasonLabel(en, 'escrow_amount_unrecorded'),
          en.reconciliationUnrecordedEscrow);
      expect(escrowFailureReasonLabel(en, 'implausible_speed'),
          en.reconciliationImplausibleSpeed);
    });
    test('unknown humanizes, empty uses default', () {
      expect(
          escrowFailureReasonLabel(en, 'weird_new_reason'), 'Weird new reason');
      expect(
          escrowFailureReasonLabel(en, ''), en.reconciliationRequiredDefault);
    });
  });

  group('jobStatusLabel', () {
    test('known statuses reuse status copy', () {
      expect(jobStatusLabel(en, 'active'), en.statusActive);
      expect(jobStatusLabel(en, 'awaiting_price_response'),
          en.statusAwaitingPrice);
      expect(jobStatusLabel(en, 'escrow_reconciliation_required'),
          en.statusReconciliationRequired);
    });
    test('unknown humanizes', () {
      expect(jobStatusLabel(en, 'in_transit'), 'In transit');
    });
  });

  group('humanizeMachineCode', () {
    test('underscores to spaces, sentence case', () {
      expect(humanizeMachineCode('PENDING_PAYMENT'), 'Pending payment');
      expect(humanizeMachineCode('a_b_c'), 'A b c');
      expect(humanizeMachineCode(''), '');
      expect(humanizeMachineCode('   '), '');
    });
  });
}
