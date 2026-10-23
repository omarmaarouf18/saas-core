import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/verification/document_picker.dart';
import 'package:frontend/features/verification/verification_rules.dart';
import 'package:frontend/models/user_profile.dart';

import '../account/account_harness.dart';

export '../account/account_harness.dart';

/// Shared fakes for the FE-OWNER-2b verification page tests.

UserProfile owner({
  String? status,
  String? reason,
  Set<VerificationSlot> onFile = const {},
}) =>
    UserProfile(
      id: 'owner-1',
      email: 'owner@example.com',
      username: 'Nile Express',
      role: 'owner',
      kycStatus: status,
      rejectionReason: reason,
      idFrontDoc: _key(onFile, VerificationSlot.idFront, 'kyb'),
      idBackDoc: _key(onFile, VerificationSlot.idBack, 'kyb'),
      selfieDoc: _key(onFile, VerificationSlot.selfie, 'kyb'),
      businessProofDoc: _key(onFile, VerificationSlot.businessProof, 'kyb'),
    );

UserProfile courier({
  String? status,
  String? reason,
  Set<VerificationSlot> onFile = const {},
}) =>
    UserProfile(
      id: 'emp-1',
      email: 'karim@example.com',
      username: 'Karim',
      role: 'employee',
      kyeStatus: status,
      rejectionReason: reason,
      idFrontDoc: _key(onFile, VerificationSlot.idFront, 'kye'),
      idBackDoc: _key(onFile, VerificationSlot.idBack, 'kye'),
      selfieDoc: _key(onFile, VerificationSlot.selfie, 'kye'),
    );

String? _key(Set<VerificationSlot> onFile, VerificationSlot s, String kind) =>
    onFile.contains(s)
        ? '$kind/u/${s.docType}.${s == VerificationSlot.businessProof ? 'pdf' : 'jpg'}'
        : null;

const allOwnerDocs = {
  VerificationSlot.idFront,
  VerificationSlot.idBack,
  VerificationSlot.selfie,
  VerificationSlot.businessProof,
};

PickedDocument file(String name, {int size = 2048}) =>
    PickedDocument(filename: name, bytes: Uint8List(size));

/// AuthProvider fake with the upload endpoint: records each upload, holds
/// on [uploadGate], throws [uploadError] once, else stores the document and
/// (like the server) moves a completed set to review.
class FakeVerifyAuth extends FakeAuthFlow {
  FakeVerifyAuth(UserProfile user) : super(user: user, token: 'jwt');

  final List<String> uploads = [];
  Completer<void>? uploadGate;
  Object? uploadError;
  bool uploadReturns = true;

  /// What the next fetchUserProfile turns the profile into (a reviewer
  /// decision seen on refresh).
  UserProfile? nextProfile;

  @override
  Future<void> fetchUserProfile() async {
    await super.fetchUserProfile();
    if (error == null && nextProfile != null) {
      user = nextProfile;
      nextProfile = null;
      notifyListeners();
    }
  }

  @override
  Future<bool> uploadDocument({
    required String docType,
    required List<int> fileBytes,
    required String filename,
  }) async {
    uploads.add('$docType:$filename');
    if (uploadGate != null) await uploadGate!.future;
    final e = uploadError;
    if (e != null) {
      uploadError = null;
      throw e;
    }
    if (!uploadReturns) return false;
    final ext = filename.split('.').last;
    final kind = user!.role == 'owner' ? 'kyb' : 'kye';
    final key = '$kind/u/$docType.$ext';
    var u = switch (docType) {
      'id_front' => user!.copyWith(idFrontDoc: key),
      'id_back' => user!.copyWith(idBackDoc: key),
      'selfie' => user!.copyWith(selfieDoc: key),
      _ => user!.copyWith(businessProofDoc: key),
    };
    if (uploadedCount(u) == slotsFor(u.role).length) {
      u = u.role == 'owner'
          ? u.copyWith(kycStatus: 'pending_super_admin_approval')
          : u.copyWith(kyeStatus: 'pending_super_admin_approval');
    }
    user = u;
    notifyListeners();
    return true;
  }
}

/// Picker fake: returns [next] (or throws [error]) and records the source.
class FakePicker extends DocumentPicker {
  FakePicker({this.next});

  PickedDocument? next;
  Object? error;
  final List<String> picks = [];

  @override
  Future<PickedDocument?> pick(DocumentSource source,
      {required bool allowPdf}) async {
    picks.add('${source.name}:$allowPdf');
    if (error != null) throw error!;
    return next;
  }
}

/// Taps [slot]'s action, then [source] in the sheet.
Future<void> chooseFor(WidgetTester tester, VerificationSlot slot,
    {DocumentSource source = DocumentSource.gallery}) async {
  await reveal(tester, find.byKey(Key('vrf_action_${slot.docType}')));
  await tester.tap(find.byKey(Key('vrf_action_${slot.docType}')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('vrf_source_${source.name}')));
  await tester.pump();
}

/// Scrolls the page's list until [f] is built, then centres it.
Future<void> reveal(WidgetTester tester, Finder f) async {
  final list = find.descendant(
      of: find.byKey(const Key('vrf_list')), matching: find.byType(Scrollable));
  // From the top, so documents above the current position are found too.
  tester.state<ScrollableState>(list.first).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(f, 200, scrollable: list.first);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}
