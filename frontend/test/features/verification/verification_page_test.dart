import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/account/account_nav.dart';
import 'package:frontend/features/courier/courier_nav.dart';
import 'package:frontend/features/owner/owner_nav.dart';
import 'package:frontend/features/verification/document_picker.dart';
import 'package:frontend/features/verification/verification_page.dart';
import 'package:frontend/features/verification/verification_rules.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:provider/provider.dart';

import 'verification_harness.dart';

class _LiveRejections extends FakeNotificationsStream {
  final StreamController<NotificationModel> controller =
      StreamController<NotificationModel>.broadcast();

  @override
  Stream<NotificationModel> get kycRejectionStream => controller.stream;
}

Future<FakeVerifyAuth> _pump(WidgetTester tester, FakeVerifyAuth auth,
    {FakePicker? picker,
    Locale locale = en,
    NotificationsProvider? notifications}) async {
  final deps = AccountTestDeps(auth: auth);
  if (notifications != null) {
    deps.extra.add(ChangeNotifierProvider<NotificationsProvider>.value(
        value: notifications));
  }
  await pumpAccount(
      tester, deps, VerificationPage(picker: picker ?? FakePicker()),
      locale: locale);
  return auth;
}

Iterable<QdButton> _primaries(WidgetTester tester) => tester
    .widgetList<QdButton>(find.byType(QdButton))
    .where((b) => b.variant == QdButtonVariant.primary);

void main() {
  testWidgets('owner: four documents, profile fetched on open', (tester) async {
    final auth = await _pump(tester, FakeVerifyAuth(owner()));
    expect(auth.calls, contains('fetchUserProfile:'));
    expect(find.text('Business verification'), findsOneWidget);
    expect(find.byKey(const Key('vrf_status_missing')), findsOneWidget);
    expect(find.text('0 of 4 uploaded'), findsOneWidget);
    for (final s in VerificationSlot.values) {
      await reveal(tester, find.byKey(Key('vrf_slot_${s.docType}')));
    }
    await reveal(tester, find.byKey(const Key('vrf_action_id_front')));
    // One gold button: the first missing document.
    final gold = _primaries(tester).toList();
    expect(gold, hasLength(1));
    expect(gold.single.key, const Key('vrf_action_id_front'));
  });

  testWidgets('courier: three documents, KYE status', (tester) async {
    await _pump(
        tester,
        FakeVerifyAuth(courier(status: 'pending_super_admin_approval', onFile: {
          VerificationSlot.idFront,
          VerificationSlot.idBack,
          VerificationSlot.selfie
        })));
    expect(find.text('ID verification'), findsOneWidget);
    expect(find.byKey(const Key('vrf_slot_business_proof')), findsNothing);
    expect(find.byKey(const Key('vrf_status_pending')), findsOneWidget);
    expect(find.byKey(const Key('vrf_chip_selfie_inReview')), findsOneWidget);
    expect(find.text('Photo on file'), findsNWidgets(3));
    // Everything on file: replace links only, no gold button.
    expect(_primaries(tester), isEmpty);
    expect(find.text('Replace'), findsNWidgets(3));
  });

  testWidgets('rejected: reviewer note, hint, documents not accepted',
      (tester) async {
    await _pump(
        tester,
        FakeVerifyAuth(owner(
            status: 'rejected',
            reason: 'The register is expired',
            onFile: allOwnerDocs)));
    expect(find.byKey(const Key('vrf_status_rejected')), findsOneWidget);
    expect(
        find.text("Reviewer's note: The register is expired"), findsOneWidget);
    expect(find.textContaining('They go back to review'), findsOneWidget);
    await reveal(
        tester, find.byKey(const Key('vrf_chip_business_proof_notAccepted')));
    await reveal(tester, find.text('PDF on file'));
  });

  testWidgets('rejected without a reason', (tester) async {
    await _pump(tester,
        FakeVerifyAuth(owner(status: 'rejected', onFile: allOwnerDocs)));
    expect(find.textContaining('No reason was given'), findsOneWidget);
  });

  testWidgets('approved: locked, no actions', (tester) async {
    await _pump(tester,
        FakeVerifyAuth(owner(status: 'approved', onFile: allOwnerDocs)));
    expect(find.byKey(const Key('vrf_status_approved')), findsOneWidget);
    expect(find.byType(QdButton), findsNothing);
    await reveal(tester, find.text("Accepted documents can't be changed."));
    expect(find.byType(QdButton), findsNothing);
  });

  testWidgets('load error with retry', (tester) async {
    final auth = FakeVerifyAuth(owner())
      ..failNext['fetchUserProfile'] = const AuthFailure('offline');
    await _pump(tester, auth);
    expect(find.byKey(const Key('vrf_load_error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vrf_load_error')), findsNothing);
    expect(auth.calls.where((c) => c == 'fetchUserProfile:'), hasLength(2));
  });

  testWidgets('pull to refresh picks up a reviewer decision', (tester) async {
    final auth = FakeVerifyAuth(
        owner(status: 'pending_super_admin_approval', onFile: allOwnerDocs));
    await _pump(tester, auth);
    auth.nextProfile = owner(status: 'approved', onFile: allOwnerDocs);
    await tester.fling(
        find.byKey(const Key('vrf_list')), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vrf_status_approved')), findsOneWidget);
  });

  testWidgets('a rejection arriving while open refreshes the page',
      (tester) async {
    final live = _LiveRejections();
    final auth = FakeVerifyAuth(
        owner(status: 'pending_super_admin_approval', onFile: allOwnerDocs));
    await _pump(tester, auth, notifications: live);
    auth.nextProfile = owner(
        status: 'rejected', reason: 'Blurry selfie', onFile: allOwnerDocs);
    // Someone else's rejection is ignored.
    live.controller.add(NotificationModel(
        id: 'n0',
        type: 'kyc_rejected',
        tenantId: 't',
        userId: 'other',
        title: 't',
        body: 'b',
        timestamp: DateTime(2026)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vrf_status_pending')), findsOneWidget);
    live.controller.add(NotificationModel(
        id: 'n1',
        type: 'kyc_rejected',
        tenantId: 't',
        userId: 'owner-1',
        title: 't',
        body: 'b',
        timestamp: DateTime(2026)));
    await tester.pumpAndSettle();
    expect(find.text("Reviewer's note: Blurry selfie"), findsOneWidget);
  });

  group('upload', () {
    testWidgets('sheet offers camera, photos and file; progress; notice',
        (tester) async {
      final picker = FakePicker(next: file('front.jpg'));
      final auth = FakeVerifyAuth(owner())..uploadGate = Completer<void>();
      await _pump(tester, auth, picker: picker);
      await tester.tap(find.byKey(const Key('vrf_action_id_front')));
      await tester.pumpAndSettle();
      expect(find.text('Add: ID card, front'), findsOneWidget);
      expect(find.byKey(const Key('vrf_source_camera')), findsOneWidget);
      expect(find.text('JPG or PNG, up to 10 MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vrf_source_gallery')));
      await tester.pump();
      await tester.pump();
      expect(picker.picks, ['gallery:false']);
      expect(auth.uploads, ['id_front:front.jpg']);
      expect(find.byKey(const Key('vrf_progress_id_front')), findsOneWidget);
      expect(find.text('Uploading front.jpg…'), findsOneWidget);
      expect(find.byKey(const Key('vrf_action_id_front')), findsNothing);
      auth.uploadGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vrf_progress_id_front')), findsNothing);
      expect(find.text('ID card, front uploaded.'), findsOneWidget);
      expect(
          find.byKey(const Key('vrf_chip_id_front_uploaded')), findsOneWidget);
      expect(find.text('front.jpg'), findsOneWidget);
      expect(find.text('1 of 4 uploaded'), findsOneWidget);
      // The gold button moved to the next missing document.
      await reveal(tester, find.byKey(const Key('vrf_action_id_back')));
      expect(_primaries(tester).single.key, const Key('vrf_action_id_back'));
    });

    testWidgets('the commercial register file picker allows PDF',
        (tester) async {
      final picker = FakePicker(next: file('register.pdf'));
      final auth = FakeVerifyAuth(owner());
      await _pump(tester, auth, picker: picker);
      await reveal(tester, find.byKey(const Key('vrf_action_business_proof')));
      await tester.tap(find.byKey(const Key('vrf_action_business_proof')));
      await tester.pumpAndSettle();
      expect(find.text('JPG, PNG or PDF, up to 10 MB'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vrf_source_file')));
      await tester.pumpAndSettle();
      expect(picker.picks, ['file:true']);
      expect(auth.uploads, ['business_proof:register.pdf']);
    });

    testWidgets('the last document sends the set for review', (tester) async {
      final auth = FakeVerifyAuth(courier(onFile: {
        VerificationSlot.idFront,
        VerificationSlot.idBack,
      }));
      await _pump(tester, auth, picker: FakePicker(next: file('me.png')));
      await chooseFor(tester, VerificationSlot.selfie,
          source: DocumentSource.camera);
      await tester.pumpAndSettle();
      expect(find.text("All documents uploaded. They're under review now."),
          findsOneWidget);
      expect(find.byKey(const Key('vrf_status_pending')), findsOneWidget);
    });

    testWidgets('client checks stop the upload', (tester) async {
      final picker =
          FakePicker(next: file('big.jpg', size: kMaxDocumentBytes + 1));
      final auth = FakeVerifyAuth(owner());
      await _pump(tester, auth, picker: picker);
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(find.text('This file is 10.0 MB. The limit is 10 MB.'),
          findsOneWidget);
      picker.next = file('scan.pdf');
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(find.text('Use a JPG or PNG photo.'), findsOneWidget);
      picker.next = file('empty.png', size: 0);
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(
          find.text('This file is empty. Choose another one.'), findsOneWidget);
      expect(auth.uploads, isEmpty);
      // Nothing was sent, so no retry.
      expect(
          find.descendant(
              of: find.byKey(const Key('vrf_error_id_front')),
              matching: find.text('Retry')),
          findsNothing);
    });

    testWidgets('server error, retry re-sends the same file', (tester) async {
      final picker = FakePicker(next: file('front.jpg'));
      final auth = FakeVerifyAuth(owner())
        ..uploadError =
            ApiClientException('unsupported file format', statusCode: 400);
      await _pump(tester, auth, picker: picker);
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vrf_error_id_front')), findsOneWidget);
      expect(find.text('Use a JPG or PNG photo.'), findsOneWidget);
      expect(find.text('Choose another file'), findsOneWidget);
      // While the slot shows an error it has no gold button.
      expect(_primaries(tester), isEmpty);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('vrf_error_id_front')),
          matching: find.text('Retry')));
      await tester.pumpAndSettle();
      expect(auth.uploads, ['id_front:front.jpg', 'id_front:front.jpg']);
      expect(picker.picks, hasLength(1));
      expect(find.byKey(const Key('vrf_error_id_front')), findsNothing);
    });

    testWidgets('403, failed upload and a broken picker', (tester) async {
      final picker = FakePicker(next: file('front.jpg'));
      final auth = FakeVerifyAuth(owner())
        ..uploadError = ApiClientException('access denied: owner role required',
            statusCode: 403);
      await _pump(tester, auth, picker: picker);
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(find.text("This account can't upload these documents."),
          findsOneWidget);

      auth.uploadReturns = false;
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't upload the file."), findsOneWidget);

      picker.error = Exception('no camera');
      await chooseFor(tester, VerificationSlot.idBack,
          source: DocumentSource.camera);
      await tester.pumpAndSettle();
      expect(
          find.text("Couldn't open that. Try another option."), findsOneWidget);
    });

    testWidgets('backing out of the sheet or the picker sends nothing',
        (tester) async {
      final picker = FakePicker();
      final auth = FakeVerifyAuth(owner());
      await _pump(tester, auth, picker: picker);
      await tester.tap(find.byKey(const Key('vrf_action_id_front')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(picker.picks, isEmpty);
      await chooseFor(tester, VerificationSlot.idFront);
      await tester.pumpAndSettle();
      expect(picker.picks, hasLength(1));
      expect(auth.uploads, isEmpty);
      expect(find.byKey(const Key('vrf_error_id_front')), findsNothing);
    });
  });

  testWidgets('Arabic renders without overflow', (tester) async {
    await _pump(
        tester,
        FakeVerifyAuth(owner(
            status: 'rejected', reason: 'السجل منتهي', onFile: allOwnerDocs)),
        locale: ar);
    expect(tester.takeException(), isNull);
    expect(find.text('توثيق الشغل'), findsOneWidget);
  });

  group('every entry point opens the shared page', () {
    Future<void> openFrom(
        WidgetTester tester, Future<void> Function(BuildContext) open) async {
      final deps = AccountTestDeps(auth: FakeVerifyAuth(owner()));
      usePhone(tester);
      await tester.pumpWidget(authApp(
          deps,
          Builder(
              builder: (context) => TextButton(
                  onPressed: () => open(context), child: const Text('go')))));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationPage), findsOneWidget);
    }

    testWidgets('account row', (tester) async {
      await openFrom(tester, const AccountNav().openVerification);
    });

    testWidgets('courier banner and row', (tester) async {
      await openFrom(tester, const CourierNav().openVerification);
    });

    testWidgets('owner KYB banner', (tester) async {
      await openFrom(tester, const OwnerNav().openKyb);
    });
  });
}
