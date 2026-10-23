/// Rules for the shared verification page (FE-OWNER-2b): business owners
/// (KYB, `POST /auth/kyb/upload`) and couriers (KYE, `POST /auth/kye/upload`)
/// upload the same identity documents; owners add the commercial register.
///
/// The auth service keeps one status for the whole set (`kyc_status` for
/// owners, `kye_status` for couriers): empty until every document is on
/// file, then `pending_super_admin_approval`, then `approved` or `rejected`
/// with one reviewer note. An upload never checks the status, and any upload
/// that completes the set (always true after a rejection) puts it back
/// under review. So a slot's state is derived from "is a document on file"
/// plus that one status.
library;

import 'dart:typed_data';

import '../../core/api_client.dart';
import '../../models/user_profile.dart';

/// The largest file the server accepts (`http.MaxBytesReader`, 10 MB).
const int kMaxDocumentBytes = 10 * 1024 * 1024;

enum VerificationSlot {
  idFront('id_front'),
  idBack('id_back'),
  selfie('selfie'),
  businessProof('business_proof');

  const VerificationSlot(this.docType);

  /// The upload's `type` query value.
  final String docType;

  /// Only the commercial register may be a PDF (the server sniffs the bytes
  /// and accepts `application/pdf` for `business_proof` alone).
  bool get allowsPdf => this == VerificationSlot.businessProof;
}

/// The documents [role] uploads: owners all four, everyone else (couriers)
/// the three identity documents.
List<VerificationSlot> slotsFor(String? role) => role == 'owner'
    ? VerificationSlot.values
    : const [
        VerificationSlot.idFront,
        VerificationSlot.idBack,
        VerificationSlot.selfie,
      ];

/// The stored document key for [slot], or null when none is on file.
String? documentOnFile(UserProfile? user, VerificationSlot slot) {
  final key = switch (slot) {
    VerificationSlot.idFront => user?.idFrontDoc,
    VerificationSlot.idBack => user?.idBackDoc,
    VerificationSlot.selfie => user?.selfieDoc,
    VerificationSlot.businessProof => user?.businessProofDoc,
  };
  final trimmed = key?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Whether the stored key is a PDF (keys end in the sniffed extension).
bool isPdfKey(String key) => key.toLowerCase().endsWith('.pdf');

enum VerificationState { missing, incomplete, pending, approved, rejected }

/// The whole set's state: the role's status (KYB for owners, KYE for
/// couriers) first; an empty status is "missing" or "incomplete" by the
/// documents on file. Unknown non-empty statuses count as under review.
VerificationState verificationStateOf(UserProfile? user) {
  final status = user?.effectiveKycStatus.trim().toLowerCase() ?? '';
  switch (status) {
    case 'approved':
      return VerificationState.approved;
    case 'rejected':
      return VerificationState.rejected;
    case '':
      final done = uploadedCount(user);
      return done == 0
          ? VerificationState.missing
          : VerificationState.incomplete;
    default:
      return VerificationState.pending;
  }
}

int uploadedCount(UserProfile? user) =>
    slotsFor(user?.role).where((s) => documentOnFile(user, s) != null).length;

enum SlotState { needed, uploading, uploaded, inReview, accepted, notAccepted }

/// One slot's state. A running upload wins; then the set's status applies
/// to every document on file.
SlotState slotStateOf(UserProfile? user, VerificationSlot slot,
    {bool uploading = false}) {
  if (uploading) return SlotState.uploading;
  if (documentOnFile(user, slot) == null) return SlotState.needed;
  return switch (verificationStateOf(user)) {
    VerificationState.approved => SlotState.accepted,
    VerificationState.rejected => SlotState.notAccepted,
    VerificationState.pending => SlotState.inReview,
    _ => SlotState.uploaded,
  };
}

/// Documents are locked once approved (the old screen hid every action).
bool canChangeDocuments(UserProfile? user) =>
    verificationStateOf(user) != VerificationState.approved;

/// The first slot with no document: the only one with the gold button.
VerificationSlot? firstNeededSlot(UserProfile? user) {
  for (final s in slotsFor(user?.role)) {
    if (documentOnFile(user, s) == null) return s;
  }
  return null;
}

/// A file picked from the camera, the photo library or the file picker.
class PickedDocument {
  const PickedDocument({required this.filename, required this.bytes});

  final String filename;
  final Uint8List bytes;

  String get extension {
    final dot = filename.lastIndexOf('.');
    return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  }
}

enum FileProblem { empty, tooLarge, badFormat }

/// Client checks before an upload, as the old screen did (10 MB, JPG / PNG,
/// PDF only where allowed) plus an empty-file check.
FileProblem? checkDocument(PickedDocument file, VerificationSlot slot) {
  if (file.bytes.isEmpty) return FileProblem.empty;
  if (file.bytes.length > kMaxDocumentBytes) return FileProblem.tooLarge;
  const images = {'jpg', 'jpeg', 'png'};
  final ext = file.extension;
  if (images.contains(ext)) return null;
  if (ext == 'pdf' && slot.allowsPdf) return null;
  return FileProblem.badFormat;
}

/// Size in MB with one decimal, for the too-large message.
String megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

enum UploadFailure { badFormat, tooLarge, notAllowed, other }

/// Upload handler errors (auth.go UploadKYB / UploadKYE): 400 "unsupported
/// file format", 400 "file too large (max 10MB) or invalid multipart", 403
/// role required; everything else is a generic failure.
UploadFailure uploadFailureOf(Object error) {
  if (error is ApiClientException) {
    final msg = error.message.toLowerCase();
    if (error.statusCode == 403) return UploadFailure.notAllowed;
    if (error.statusCode == 400 && msg.contains('format')) {
      return UploadFailure.badFormat;
    }
    if (error.statusCode == 400 && msg.contains('too large')) {
      return UploadFailure.tooLarge;
    }
  }
  return UploadFailure.other;
}
