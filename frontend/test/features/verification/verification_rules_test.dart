import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/verification/verification_rules.dart';

import 'verification_harness.dart';

void main() {
  group('slots', () {
    test('owners upload four documents, couriers three', () {
      expect(slotsFor('owner'), VerificationSlot.values);
      expect(slotsFor('employee'), [
        VerificationSlot.idFront,
        VerificationSlot.idBack,
        VerificationSlot.selfie,
      ]);
      expect(slotsFor(null), hasLength(3));
    });

    test('only the commercial register may be a PDF', () {
      expect(VerificationSlot.values.where((s) => s.allowsPdf).toList(),
          [VerificationSlot.businessProof]);
      expect(VerificationSlot.values.map((s) => s.docType),
          ['id_front', 'id_back', 'selfie', 'business_proof']);
    });

    test('blank document keys count as missing', () {
      final u = owner().copyWith(idFrontDoc: '  ');
      expect(documentOnFile(u, VerificationSlot.idFront), isNull);
      expect(
          documentOnFile(owner(onFile: {VerificationSlot.selfie}),
              VerificationSlot.selfie),
          'kyb/u/selfie.jpg');
    });
  });

  group('state', () {
    test('empty status: missing or incomplete by the documents on file', () {
      expect(verificationStateOf(owner()), VerificationState.missing);
      expect(verificationStateOf(owner(onFile: {VerificationSlot.idBack})),
          VerificationState.incomplete);
      expect(verificationStateOf(null), VerificationState.missing);
    });

    test('server statuses', () {
      expect(verificationStateOf(owner(status: 'pending_super_admin_approval')),
          VerificationState.pending);
      expect(verificationStateOf(owner(status: 'approved')),
          VerificationState.approved);
      expect(verificationStateOf(owner(status: 'REJECTED')),
          VerificationState.rejected);
      expect(verificationStateOf(owner(status: 'something_new')),
          VerificationState.pending);
    });

    test('couriers use the KYE status, not the KYB one', () {
      final c = courier(status: 'approved').copyWith(kycStatus: 'rejected');
      expect(verificationStateOf(c), VerificationState.approved);
    });

    test('slot states follow the set status for documents on file', () {
      final docs = {VerificationSlot.idFront};
      expect(slotStateOf(owner(onFile: docs), VerificationSlot.idFront),
          SlotState.uploaded);
      expect(slotStateOf(owner(onFile: docs), VerificationSlot.idBack),
          SlotState.needed);
      expect(
          slotStateOf(owner(onFile: allOwnerDocs, status: 'rejected'),
              VerificationSlot.selfie),
          SlotState.notAccepted);
      expect(
          slotStateOf(
              owner(
                  onFile: allOwnerDocs, status: 'pending_super_admin_approval'),
              VerificationSlot.selfie),
          SlotState.inReview);
      expect(
          slotStateOf(owner(onFile: allOwnerDocs, status: 'approved'),
              VerificationSlot.selfie),
          SlotState.accepted);
      expect(slotStateOf(owner(), VerificationSlot.selfie, uploading: true),
          SlotState.uploading);
    });

    test('locked once approved; gold goes to the first missing document', () {
      expect(canChangeDocuments(owner(status: 'approved')), isFalse);
      expect(canChangeDocuments(owner(status: 'rejected')), isTrue);
      expect(firstNeededSlot(owner(onFile: {VerificationSlot.idFront})),
          VerificationSlot.idBack);
      expect(firstNeededSlot(owner(onFile: allOwnerDocs)), isNull);
    });
  });

  group('file checks', () {
    test('empty, too large, format', () {
      expect(checkDocument(file('a.jpg', size: 0), VerificationSlot.idFront),
          FileProblem.empty);
      expect(
          checkDocument(file('a.jpg', size: kMaxDocumentBytes + 1),
              VerificationSlot.idFront),
          FileProblem.tooLarge);
      expect(
          checkDocument(
              file('a.jpg', size: kMaxDocumentBytes), VerificationSlot.idFront),
          isNull);
      expect(checkDocument(file('A.JPEG'), VerificationSlot.selfie), isNull);
      expect(checkDocument(file('a.png'), VerificationSlot.selfie), isNull);
      expect(checkDocument(file('a.pdf'), VerificationSlot.idFront),
          FileProblem.badFormat);
      expect(
          checkDocument(file('a.pdf'), VerificationSlot.businessProof), isNull);
      expect(checkDocument(file('scan'), VerificationSlot.businessProof),
          FileProblem.badFormat);
      expect(checkDocument(file('a.heic'), VerificationSlot.idBack),
          FileProblem.badFormat);
    });

    test('megabytes with one decimal', () {
      expect(megabytes(12 * 1024 * 1024 + 300 * 1024), '12.3');
    });

    test('picked document extension', () {
      expect(PickedDocument(filename: 'x.Y.PnG', bytes: Uint8List(1)).extension,
          'png');
      expect(
          PickedDocument(filename: 'noext', bytes: Uint8List(1)).extension, '');
    });
  });

  test('upload failures from the handler errors', () {
    expect(
        uploadFailureOf(
            ApiClientException('unsupported file format', statusCode: 400)),
        UploadFailure.badFormat);
    expect(
        uploadFailureOf(ApiClientException(
            'file too large (max 10MB) or invalid multipart',
            statusCode: 400)),
        UploadFailure.tooLarge);
    expect(
        uploadFailureOf(ApiClientException('access denied: owner role required',
            statusCode: 403)),
        UploadFailure.notAllowed);
    expect(
        uploadFailureOf(
            ApiClientException('internal server error', statusCode: 500)),
        UploadFailure.other);
    expect(uploadFailureOf(Exception('x')), UploadFailure.other);
  });
}
