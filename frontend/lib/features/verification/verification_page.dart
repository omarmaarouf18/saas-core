import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/notification_model.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import '../account/account_nav.dart';
import 'document_picker.dart';
import 'verification_rules.dart';

/// Verification (FE-OWNER-2b), shared by business owners (KYB) and
/// couriers (KYE). Replaces KycDocumentUploadScreen for the redesigned
/// owner and courier apps.
///
/// Behaviour kept from the old screen: the profile is re-fetched on open and
/// on pull to refresh (guarded against double runs) with a retryable error;
/// the set's status with the reviewer's reason when rejected; one card per
/// document (three for couriers, four for owners) with its state; camera /
/// photos / file choice (PDF only for the commercial register); 10 MB and
/// format checks before sending; per-document upload state and error with
/// retry; only the first missing document gets the gold button; everything
/// is locked once approved. New: the retry re-sends the same file instead of
/// asking again, an empty-file check, server format / size errors in plain
/// words, the page refreshes when a rejection arrives while it is open.
/// Dropped: the "remove selection" button (it only cleared the local
/// preview, nothing on the server) and the app-bar refresh button (pull to
/// refresh and the error's retry remain).
class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key, this.picker = const DocumentPicker()});

  final DocumentPicker picker;

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const VerificationPage()));

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  bool _refreshing = false;
  String? _loadError;
  final Set<VerificationSlot> _uploading = {};
  final Map<VerificationSlot, String> _errors = {};

  /// The last file sent per slot: its name is shown, and the retry re-sends
  /// it.
  final Map<VerificationSlot, PickedDocument> _sent = {};
  StreamSubscription<NotificationModel>? _rejections;

  @override
  void initState() {
    super.initState();
    try {
      _rejections = context
          .read<NotificationsProvider>()
          .kycRejectionStream
          .listen(_onRejection);
    } catch (_) {
      // No live notifications here (tests, signed-out): pull to refresh.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _rejections?.cancel();
    super.dispose();
  }

  void _onRejection(NotificationModel n) {
    final me = context.read<AuthProvider>().user?.id;
    if (mounted && me != null && n.userId == me) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() {
      _refreshing = true;
      _loadError = null;
    });
    await auth.fetchUserProfile();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _loadError = auth.error;
    });
  }

  Future<void> _choose(VerificationSlot slot) async {
    if (_uploading.contains(slot)) return;
    final l10n = context.l10n;
    final source = await showDocumentSourceSheet(context, _title(l10n, slot),
        allowPdf: slot.allowsPdf);
    if (source == null || !mounted) return;
    PickedDocument? file;
    try {
      file = await widget.picker.pick(source, allowPdf: slot.allowsPdf);
    } catch (_) {
      if (mounted) setState(() => _errors[slot] = l10n.vrfErrPicker);
      return;
    }
    if (file == null || !mounted) return;
    await _upload(slot, file);
  }

  Future<void> _upload(VerificationSlot slot, PickedDocument file) async {
    if (_uploading.contains(slot)) return;
    final l10n = context.l10n;
    final problem = checkDocument(file, slot);
    if (problem != null) {
      setState(() {
        _sent.remove(slot);
        _errors[slot] = switch (problem) {
          FileProblem.empty => l10n.vrfErrEmpty,
          FileProblem.tooLarge =>
            l10n.vrfErrTooLarge(megabytes(file.bytes.length)),
          FileProblem.badFormat =>
            slot.allowsPdf ? l10n.vrfErrFormatDoc : l10n.vrfErrFormatPhoto,
        };
      });
      return;
    }
    final auth = context.read<AuthProvider>();
    final wasPending =
        verificationStateOf(auth.user) == VerificationState.pending;
    setState(() {
      _uploading.add(slot);
      _errors.remove(slot);
      _sent[slot] = file;
    });
    String? error;
    try {
      final ok = await auth.uploadDocument(
        docType: slot.docType,
        fileBytes: file.bytes,
        filename: file.filename,
      );
      if (!ok) error = l10n.vrfErrUpload;
    } catch (e) {
      error = switch (uploadFailureOf(e)) {
        UploadFailure.badFormat =>
          slot.allowsPdf ? l10n.vrfErrFormatDoc : l10n.vrfErrFormatPhoto,
        UploadFailure.tooLarge =>
          l10n.vrfErrTooLarge(megabytes(file.bytes.length)),
        UploadFailure.notAllowed => l10n.vrfErrNotAllowed,
        UploadFailure.other => friendlyErrorMessage(e),
      };
    }
    if (!mounted) return;
    setState(() {
      _uploading.remove(slot);
      if (error != null) _errors[slot] = error;
    });
    if (error == null) {
      // uploadDocument re-fetched the profile: a completed set is now
      // under review.
      final nowPending =
          verificationStateOf(auth.user) == VerificationState.pending;
      showAccountNotice(
          context,
          nowPending && !wasPending
              ? l10n.vrfSentForReview
              : l10n.vrfUploadedNotice(_title(l10n, slot)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final isOwner = user?.role == 'owner';
    final slots = slotsFor(user?.role);
    final editable = canChangeDocuments(user);
    final gold = firstNeededSlot(user);

    return Scaffold(
      key: const Key('verification_page'),
      backgroundColor: c.surface,
      appBar: accountAppBar(
          context, isOwner ? l10n.vrfTitleOwner : l10n.vrfTitleCourier),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('vrf_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
          children: [
            if (_loadError != null) ...[
              QdBanner(
                key: const Key('vrf_load_error'),
                tone: QdBannerTone.warning,
                message: l10n.vrfLoadError,
                actionLabel: l10n.retry,
                onAction: _refresh,
              ),
              const SizedBox(height: QdSpace.x3),
            ],
            _StatusCard(user: user),
            const SizedBox(height: QdSpace.x5),
            Row(
              children: [
                Expanded(
                  child:
                      QdSectionHeader(title: l10n.vrfDocsHeader, small: true),
                ),
                Text(
                  l10n.vrfDocsCount(uploadedCount(user), slots.length),
                  key: const Key('vrf_count'),
                  style: QdText.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: QdSpace.x2),
            for (final slot in slots) ...[
              _SlotCard(
                key: Key('vrf_slot_${slot.docType}'),
                slot: slot,
                title: _title(l10n, slot),
                hint: _hint(l10n, slot),
                state: slotStateOf(user, slot,
                    uploading: _uploading.contains(slot)),
                onFile: documentOnFile(user, slot),
                sent: _sent[slot],
                error: _errors[slot],
                editable: editable,
                primary: editable && slot == gold,
                onChoose: () => _choose(slot),
                onRetry: _sent[slot] == null
                    ? null
                    : () => _upload(slot, _sent[slot]!),
              ),
              const SizedBox(height: QdSpace.x3),
            ],
            Text(
              editable
                  ? (isOwner ? l10n.vrfRulesOwner : l10n.vrfRulesCourier)
                  : l10n.vrfLocked,
              key: const Key('vrf_rules'),
              style: QdText.caption.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _title(AppLocalizations l10n, VerificationSlot s) => switch (s) {
      VerificationSlot.idFront => l10n.vrfSlotIdFront,
      VerificationSlot.idBack => l10n.vrfSlotIdBack,
      VerificationSlot.selfie => l10n.vrfSlotSelfie,
      VerificationSlot.businessProof => l10n.vrfSlotBusiness,
    };

String _hint(AppLocalizations l10n, VerificationSlot s) => switch (s) {
      VerificationSlot.idFront => l10n.vrfSlotIdFrontHint,
      VerificationSlot.idBack => l10n.vrfSlotIdBackHint,
      VerificationSlot.selfie => l10n.vrfSlotSelfieHint,
      VerificationSlot.businessProof => l10n.vrfSlotBusinessHint,
    };

IconData _icon(VerificationSlot s) => switch (s) {
      VerificationSlot.idFront => Icons.badge_outlined,
      VerificationSlot.idBack => Icons.flip_to_back_outlined,
      VerificationSlot.selfie => Icons.face_outlined,
      VerificationSlot.businessProof => Icons.storefront_outlined,
    };

/// The whole set: what is going on and what to do next.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final state = verificationStateOf(user);
    final total = slotsFor(user?.role).length;
    final isOwner = user?.role == 'owner';
    final reason = user?.rejectionReason?.trim() ?? '';
    final (IconData icon, Color fg, Color bg) = switch (state) {
      VerificationState.approved => (
          Icons.verified_outlined,
          c.success,
          c.successBg
        ),
      VerificationState.rejected => (Icons.error_outline, c.danger, c.dangerBg),
      VerificationState.pending => (
          Icons.hourglass_top,
          c.warning,
          c.warningBg
        ),
      _ => (Icons.upload_file_outlined, c.textPrimary, c.fillMuted),
    };
    final title = switch (state) {
      VerificationState.missing => l10n.vrfStateMissingTitle,
      VerificationState.incomplete =>
        l10n.vrfStateIncompleteTitle(uploadedCount(user), total),
      VerificationState.pending => l10n.vrfStatePendingTitle,
      VerificationState.approved => l10n.vrfStateApprovedTitle,
      VerificationState.rejected => l10n.vrfStateRejectedTitle,
    };
    final body = switch (state) {
      VerificationState.missing => isOwner
          ? l10n.vrfStateMissingOwner(total)
          : l10n.vrfStateMissingCourier(total),
      VerificationState.incomplete => l10n.vrfStateIncompleteBody,
      VerificationState.pending => l10n.vrfStatePendingBody,
      VerificationState.approved => l10n.vrfStateApprovedBody,
      VerificationState.rejected => reason.isEmpty
          ? l10n.vrfRejectedNoReason
          : l10n.vrfRejectedReason(reason),
    };

    return QdCard(
      key: Key('vrf_status_${state.name}'),
      subtle: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: QdSize.iconTile,
            height: QdSize.iconTile,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(QdRadius.sm),
            ),
            child: Icon(icon, size: QdSize.icon, color: fg),
          ),
          const SizedBox(width: QdSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title,
                      style: QdText.rowTitle.copyWith(color: c.textPrimary)),
                ),
                const SizedBox(height: QdSpace.x1),
                Text(body,
                    key: const Key('vrf_status_body'),
                    style: QdText.body.copyWith(color: c.textPrimary)),
                if (state == VerificationState.rejected) ...[
                  const SizedBox(height: QdSpace.x2),
                  Text(l10n.vrfRejectedHint,
                      style: QdText.secondary.copyWith(color: c.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    super.key,
    required this.slot,
    required this.title,
    required this.hint,
    required this.state,
    required this.onFile,
    required this.sent,
    required this.error,
    required this.editable,
    required this.primary,
    required this.onChoose,
    required this.onRetry,
  });

  final VerificationSlot slot;
  final String title;
  final String hint;
  final SlotState state;
  final String? onFile;
  final PickedDocument? sent;
  final String? error;
  final bool editable;
  final bool primary;
  final VoidCallback onChoose;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final uploading = state == SlotState.uploading;
    final (String chip, QdTone tone) = switch (state) {
      SlotState.needed => (l10n.vrfSlotNeeded, QdTone.neutral),
      SlotState.uploading => (l10n.vrfSlotUploading, QdTone.neutral),
      SlotState.uploaded => (l10n.vrfSlotUploaded, QdTone.success),
      SlotState.inReview => (l10n.vrfSlotInReview, QdTone.warning),
      SlotState.accepted => (l10n.vrfSlotAccepted, QdTone.success),
      SlotState.notAccepted => (l10n.vrfSlotNotAccepted, QdTone.danger),
    };
    // The file sent from this page, else what the server has on file.
    final fileLine = sent != null && onFile != null
        ? sent!.filename
        : onFile == null
            ? null
            : isPdfKey(onFile!)
                ? l10n.vrfOnFilePdf
                : l10n.vrfOnFilePhoto;

    return QdCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              QdIconTile(icon: _icon(slot)),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Text(hint,
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x3),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QdStatusChip(
                        key: Key('vrf_chip_${slot.docType}_${state.name}'),
                        label: chip,
                        tone: tone),
                    if (fileLine != null && !uploading) ...[
                      const SizedBox(height: QdSpace.x1),
                      Text(
                        fileLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QdText.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (editable && !uploading && onFile != null)
                QdButton.text(
                  key: Key('vrf_action_${slot.docType}'),
                  label: l10n.vrfReplace,
                  icon: Icons.sync,
                  small: true,
                  onPressed: onChoose,
                ),
            ],
          ),
          if (uploading) ...[
            const SizedBox(height: QdSpace.x3),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                key: Key('vrf_progress_${slot.docType}'),
                minHeight: 4,
                color: c.navy,
                backgroundColor: c.border,
              ),
            ),
            const SizedBox(height: QdSpace.x2),
            Text(
              l10n.vrfUploadingFile(sent?.filename ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QdText.caption.copyWith(color: c.textSecondary),
            ),
          ],
          if (error != null && !uploading) ...[
            const SizedBox(height: QdSpace.x3),
            QdBanner(
              key: Key('vrf_error_${slot.docType}'),
              tone: QdBannerTone.danger,
              message: error!,
              actionLabel: onRetry == null ? null : l10n.retry,
              onAction: onRetry,
            ),
          ],
          if (editable && !uploading && onFile == null) ...[
            const SizedBox(height: QdSpace.x3),
            _upload(l10n),
          ],
        ],
      ),
    );
  }

  Widget _upload(AppLocalizations l10n) {
    final key = Key('vrf_action_${slot.docType}');
    final label = error != null && onRetry != null
        ? l10n.vrfChooseAnother
        : l10n.vrfUpload;
    return primary && error == null
        ? QdButton(
            key: key,
            label: label,
            icon: Icons.upload_outlined,
            fullWidth: true,
            onPressed: onChoose)
        : QdButton.secondary(
            key: key,
            label: label,
            icon: Icons.upload_outlined,
            fullWidth: true,
            onPressed: onChoose);
  }
}
