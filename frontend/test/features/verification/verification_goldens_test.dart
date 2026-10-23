import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/verification/verification_page.dart';
import 'package:frontend/features/verification/verification_rules.dart';
import 'package:frontend/models/user_profile.dart';

import '../customer/customer_harness.dart' as cust;
import 'verification_harness.dart';

// Golden snapshots of the FE-OWNER-2b verification page at 360x800, light,
// AR-RTL and EN-LTR, Plex font.
//
// Regenerate after an intentional change, with the CI Flutter version:
//   flutter test --update-goldens test/features/verification/verification_goldens_test.dart

String _t(Locale l, String enText, String arText) =>
    l.languageCode == 'ar' ? arText : enText;

typedef _Case = (
  UserProfile Function(Locale),
  Future<void> Function(WidgetTester, FakeVerifyAuth, FakePicker)
);

Future<void> _none(WidgetTester t, FakeVerifyAuth a, FakePicker p) async {}

final Map<String, _Case> _cases = {
  // Owner, nothing uploaded yet: four slots, one gold button.
  'owner_missing': ((_) => owner(), _none),
  // Owner, rejected with the reviewer's note.
  'owner_rejected': (
    (l) => owner(
        status: 'rejected',
        reason: _t(l, 'The commercial register photo is cut off.',
            'صورة السجل التجاري مقصوصة.'),
        onFile: allOwnerDocs),
    _none
  ),
  // Courier, two of three uploaded, the selfie uploading.
  'courier_uploading': (
    (_) => courier(onFile: {VerificationSlot.idFront, VerificationSlot.idBack}),
    (tester, auth, picker) async {
      auth.uploadGate = Completer<void>();
      picker.next = file('selfie_2026.jpg');
      await chooseFor(tester, VerificationSlot.selfie);
      // The progress bar animates: fixed frames, no settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  ),
  // Courier, approved: locked.
  'courier_approved': (
    (_) => courier(status: 'approved', onFile: {
          VerificationSlot.idFront,
          VerificationSlot.idBack,
          VerificationSlot.selfie
        }),
    _none
  ),
  // The camera / photos / file sheet for the commercial register.
  'source_sheet': (
    (_) => owner(onFile: {
          VerificationSlot.idFront,
          VerificationSlot.idBack,
          VerificationSlot.selfie
        }),
    (tester, auth, picker) async {
      await reveal(tester, find.byKey(const Key('vrf_action_business_proof')));
      await tester.tap(find.byKey(const Key('vrf_action_business_proof')));
      await tester.pumpAndSettle();
    }
  ),
  // A server error on one slot, with retry.
  'upload_error': (
    (_) => owner(onFile: {VerificationSlot.idFront}),
    (tester, auth, picker) async {
      auth.uploadReturns = false;
      picker.next = file('id_back.png');
      await chooseFor(tester, VerificationSlot.idBack);
      await tester.pumpAndSettle();
      // Let the notice-free state settle and show the error card.
      await reveal(tester, find.byKey(const Key('vrf_error_id_back')));
    }
  ),
};

void main() {
  setUpAll(cust.loadPlexFont);

  _cases.forEach((name, entry) {
    final (user, setup) = entry;
    for (final locale in bothLocales) {
      final dir = locale == ar ? 'ar_rtl' : 'en_ltr';
      testWidgets('GOLDEN verification $name $dir', (tester) async {
        final auth = FakeVerifyAuth(user(locale));
        final picker = FakePicker();
        await pumpAccount(tester, AccountTestDeps(auth: auth),
            VerificationPage(picker: picker),
            locale: locale);
        await setup(tester, auth, picker);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/vrf_${name}_${dir}_360x800.png'),
        );
        auth.uploadGate?.complete();
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
