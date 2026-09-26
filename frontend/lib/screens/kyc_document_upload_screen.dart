import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';

import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_success_banner.dart';

/// Descriptor for a picked file to be uploaded.
class PickedDocumentFile {
  final String filename;
  final Uint8List bytes;

  const PickedDocumentFile({
    required this.filename,
    required this.bytes,
  });
}

/// Typedef for custom file picker override (useful for testing and custom UI).
typedef FilePickerCallback = Future<PickedDocumentFile?> Function(
  BuildContext context,
  String slotKey,
  bool allowPdf,
);

class KycDocumentUploadScreen extends StatefulWidget {
  final FilePickerCallback? onPickFile;

  const KycDocumentUploadScreen({
    super.key,
    this.onPickFile,
  });

  @override
  State<KycDocumentUploadScreen> createState() =>
      _KycDocumentUploadScreenState();
}

class _KycDocumentUploadScreenState extends State<KycDocumentUploadScreen> {
  // Track per-slot state: uploading flag, error string, and newly picked file preview
  final Map<String, bool> _uploadingSlots = {};
  final Map<String, String?> _slotErrors = {};
  final Map<String, PickedDocumentFile?> _pickedFiles = {};
  // Audit A10: refresh busy flag — the AppBar button and pull-to-refresh
  // share _refreshUserData, and both must show a busy state + refuse
  // re-trigger until the fetch resolves (previously zero feedback).
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshUserData();
    });
  }

  Future<void> _refreshUserData() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      await auth.fetchUserProfile();
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  /// Consolidated bottom sheet picker for camera, gallery, and optional PDF selection.
  Future<String?> _showSourcePickerBottomSheet(
    BuildContext context, {
    required bool allowPdf,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allowPdf
                  ? l10n.selectFileSourceTitle
                  : l10n.selectImageSourceTitle,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: Icon(Icons.camera_alt,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(l10n.kycTakeCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(l10n.kycChooseGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (allowPdf)
              ListTile(
                leading: Icon(Icons.picture_as_pdf,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(l10n.kycSelectPdf),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
          ],
        ),
      ),
    );
  }

  Future<PickedDocumentFile?> _defaultPickFile(
      BuildContext context, String slotKey, bool allowPdf) async {
    final source =
        await _showSourcePickerBottomSheet(context, allowPdf: allowPdf);

    if (!context.mounted || source == null) return null;

    if (source == 'camera') {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        return PickedDocumentFile(filename: xfile.name, bytes: bytes);
      }
    } else if (source == 'gallery') {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        return PickedDocumentFile(filename: xfile.name, bytes: bytes);
      }
    } else if (source == 'pdf' && allowPdf) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          return PickedDocumentFile(filename: file.name, bytes: file.bytes!);
        }
      }
    }
    return null;
  }

  Future<void> _handleSlotUpload(
      String slotKey, String slotTitle, bool allowPdf) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _slotErrors[slotKey] = null;
    });

    final pickerFunc = widget.onPickFile ?? _defaultPickFile;
    final pickedFile = await pickerFunc(context, slotKey, allowPdf);

    if (!mounted) return;
    if (pickedFile == null) return;

    // 1. Client-side file size validation: max 10MB (10 * 1024 * 1024 bytes)
    const maxSizeBytes = 10 * 1024 * 1024;
    if (pickedFile.bytes.length > maxSizeBytes) {
      final l10n = context.l10n;
      setState(() {
        _slotErrors[slotKey] = l10n.fileSizeExceededError(
            (pickedFile.bytes.length / (1024 * 1024)).toStringAsFixed(1));
      });
      return;
    }

    // 2. Client-side format validation
    final ext = pickedFile.filename.contains('.')
        ? pickedFile.filename.split('.').last.toLowerCase()
        : '';

    final validImageExts = ['jpg', 'jpeg', 'png'];
    final isValidImage = validImageExts.contains(ext);
    final isValidPdf = allowPdf && ext == 'pdf';

    if (!isValidImage && !isValidPdf) {
      setState(() {
        _slotErrors[slotKey] = allowPdf
            ? l10n.kycInvalidFormatDocs(slotTitle)
            : l10n.kycInvalidFormatImages(slotTitle);
      });
      return;
    }

    // Save local preview
    setState(() {
      _pickedFiles[slotKey] = pickedFile;
      _uploadingSlots[slotKey] = true;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final success = await auth.uploadDocument(
        docType: slotKey,
        fileBytes: pickedFile.bytes,
        filename: pickedFile.filename,
      );

      if (!success) {
        setState(() {
          _slotErrors[slotKey] = ErrorMessages.genericFallback;
        });
      }
    } catch (e) {
      setState(() {
        _slotErrors[slotKey] = friendlyErrorMessage(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _uploadingSlots[slotKey] = false;
        });
      }
    }
  }

  String? _getExistingDocPath(UserProfile? authUser, String slotKey) {
    switch (slotKey) {
      case 'id_front':
        return authUser?.idFrontDoc;
      case 'id_back':
        return authUser?.idBackDoc;
      case 'selfie':
        return authUser?.selfieDoc;
      case 'business_proof':
        return authUser?.businessProofDoc;
      default:
        return null;
    }
  }

  Widget _buildStatusBanner({
    required String displayStatus,
    required bool isApproved,
    required bool isPending,
    required bool isRejected,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return ThemedPanel(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdBorder,
        border: Border(
          left: BorderSide(
            color: isApproved
                ? context.semanticColors.success
                : (isRejected
                    ? Theme.of(context).colorScheme.error
                    : (isPending
                        ? AppColors.secondary
                        : Theme.of(context).colorScheme.primary)),
            width: 4,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isApproved
                      ? Icons.check_circle_outline
                      : (isRejected
                          ? Icons.error_outline
                          : (isPending ? Icons.schedule : Icons.info_outline)),
                  color: isApproved
                      ? context.semanticColors.success
                      : (isRejected
                          ? Theme.of(context).colorScheme.error
                          : (isPending
                              ? AppColors.secondary
                              : Theme.of(context).colorScheme.primary)),
                  size: AppIconSize.smMd,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    context.l10n.verificationStatusCardTitle,
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                StatusBadge(status: displayStatus),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isApproved
                  ? l10n.kycApprovedBanner
                  : (isPending
                      ? l10n.kycPendingBanner
                      : (isRejected
                          ? l10n.kycRejectedBanner
                          : l10n.kycUploadAllBanner)),
              style: AppTypography.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ));
  }

  Widget _buildRejectionReasonBanner(AppLocalizations l10n, String reason) {
    return ThemedErrorBanner(
      message: l10n.rejectionReasonMessage(reason),
      onRetry: _refreshUserData,
    );
  }

  Widget _buildApprovedLockedBanner() {
    return ThemedSuccessBanner(
      message: context.l10n.documentsLockedMessage,
    );
  }

  Widget _buildDocumentSlotCard({
    required Map<String, dynamic> slot,
    required UserProfile? user,
    required bool isApproved,
    // Audit A9: only the first incomplete slot keeps the focal
    // PrimaryButton; remaining incomplete slots render an outlined
    // SecondaryButton so Verify/Upload attention has one target.
    required bool isFirstIncomplete,
  }) {
    final slotKey = slot['key'] as String;
    final title = slot['title'] as String;
    final subtitle = slot['subtitle'] as String;
    final allowPdf = slot['allowPdf'] as bool;
    final icon = slot['icon'] as IconData;

    final isUploading = _uploadingSlots[slotKey] ?? false;
    final slotError = _slotErrors[slotKey];
    final localPicked = _pickedFiles[slotKey];
    final existingPath = _getExistingDocPath(user, slotKey);

    final isUploaded = (existingPath != null && existingPath.isNotEmpty) ||
        localPicked != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: ThemedCard(
        padding: AppSpacing.lg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ThemedPanel(
                    color: isUploaded
                        ? context.semanticColors.success.withValues(alpha: 0.12)
                        : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                    borderRadius: AppRadius.smBorder,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      icon,
                      color: isUploaded
                          ? context.semanticColors.success
                          : Theme.of(context).colorScheme.primary,
                      size: 26,
                    )),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: AppTypography.titleMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          if (isUploaded)
                            const StatusBadge(
                              status: 'uploaded',
                              compact: true,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Document Preview Row if Uploaded
            AnimatedSwitcher(
              duration: AppMotion.durationMedium,
              switchInCurve: AppMotion.curveStateChange,
              switchOutCurve: AppMotion.curveStateChange,
              child: isUploaded
                  ? Padding(
                      key: ValueKey('preview_$slotKey'),
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: ThemedPanel(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: AppRadius.smBorder,
                          border: Border.all(
                            color:
                                AppColors.outlineVariant.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: Row(
                            children: [
                              if (localPicked != null &&
                                  !localPicked.filename
                                      .toLowerCase()
                                      .endsWith('.pdf'))
                                ClipRRect(
                                  borderRadius: AppRadius.smBorder,
                                  child: Image.memory(
                                    localPicked.bytes,
                                    width: 48,
                                    height: 48,
                                    cacheWidth: 144,
                                    cacheHeight: 144,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Icon(
                                      Icons.image,
                                      size: 36,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                )
                              else if (allowPdf ||
                                  (localPicked?.filename
                                          .toLowerCase()
                                          .endsWith('.pdf') ??
                                      false))
                                Icon(
                                  Icons.picture_as_pdf,
                                  size: 36,
                                  color: Theme.of(context).colorScheme.error,
                                )
                              else
                                Icon(
                                  Icons.insert_drive_file,
                                  size: 36,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  localPicked != null
                                      ? localPicked.filename
                                      : context.l10n.documentOnFile(
                                          existingPath!.split('/').last),
                                  style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!isApproved)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  color: Theme.of(context).colorScheme.error,
                                  tooltip: context.l10n.removeSelectionAction,
                                  onPressed: isUploading
                                      ? null
                                      : () {
                                          setState(() {
                                            _pickedFiles.remove(slotKey);
                                          });
                                        },
                                ),
                            ],
                          )),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty_preview')),
            ),

            // Per-slot Error Display with Retry action
            if (slotError != null) ...[
              const SizedBox(height: AppSpacing.md),
              ThemedErrorBanner(
                message: slotError,
                onRetry: isApproved
                    ? null
                    : () => _handleSlotUpload(slotKey, title, allowPdf),
                onDismiss: () {
                  setState(() {
                    _slotErrors[slotKey] = null;
                  });
                },
              ),
            ],

            const SizedBox(height: AppSpacing.md),

            // Slot Action Button (Upload / Replace / Loading)
            AnimatedSwitcher(
              duration: AppMotion.durationMedium,
              switchInCurve: AppMotion.curveStateChange,
              switchOutCurve: AppMotion.curveStateChange,
              child: !isApproved
                  ? (isUploaded
                      ? SecondaryButton(
                          key: ValueKey('btn_replace_$slotKey'),
                          text: context.l10n.replaceDocumentBtn,
                          icon: Icons.refresh,
                          isLoading: isUploading,
                          onPressed: isUploading
                              ? null
                              : () =>
                                  _handleSlotUpload(slotKey, title, allowPdf),
                        )
                      : isFirstIncomplete
                          ? PrimaryButton(
                              key: ValueKey('btn_upload_$slotKey'),
                              text: context.l10n.uploadDocumentBtn,
                              icon: Icons.upload_file,
                              trailingIcon: Icons.arrow_forward,
                              isLoading: isUploading,
                              onPressed: isUploading
                                  ? null
                                  : () => _handleSlotUpload(
                                      slotKey, title, allowPdf),
                            )
                          : SecondaryButton(
                              key: ValueKey('btn_upload_$slotKey'),
                              text: context.l10n.uploadDocumentBtn,
                              icon: Icons.upload_file,
                              isOutlined: true,
                              isLoading: isUploading,
                              onPressed: isUploading
                                  ? null
                                  : () => _handleSlotUpload(
                                      slotKey, title, allowPdf),
                            ))
                  : const SizedBox.shrink(key: ValueKey('slot_approved')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    final isOwner = user?.role == 'owner';
    final roleTitle = isOwner ? l10n.ownerKybTitle : l10n.employeeKyeTitle;

    final status = user?.effectiveKycStatus ?? '';
    final displayStatus = status.isEmpty ? 'unverified' : status;

    final isApproved = user?.isApproved ?? false;
    final isRejected = user?.isRejected ?? false;
    final isPending = user?.isPendingApproval ?? false;

    final slots = [
      {
        'key': 'id_front',
        'title': l10n.idFrontTitle,
        'subtitle': l10n.idFrontDesc,
        'allowPdf': false,
        'icon': Icons.badge_outlined,
      },
      {
        'key': 'id_back',
        'title': l10n.idBackTitle,
        'subtitle': l10n.idBackDesc,
        'allowPdf': false,
        'icon': Icons.flip_to_back_outlined,
      },
      {
        'key': 'selfie',
        'title': l10n.selfieTitle,
        'subtitle': l10n.selfieDesc,
        'allowPdf': false,
        'icon': Icons.account_box_outlined,
      },
      if (isOwner)
        {
          'key': 'business_proof',
          'title': l10n.businessProofTitle,
          'subtitle': l10n.businessProofDesc,
          'allowPdf': true,
          'icon': Icons.business_outlined,
        },
    ];

    // Audit A9: first incomplete slot key — only it keeps the focal
    // PrimaryButton; remaining incomplete slots are demoted to outlined
    // SecondaryButtons in _buildDocumentSlotCard.
    String? firstIncompleteKey;
    for (final slot in slots) {
      final key = slot['key'] as String;
      final existing = _getExistingDocPath(user, key);
      final picked = _pickedFiles[key];
      if ((existing == null || existing.isEmpty) && picked == null) {
        firstIncompleteKey = key;
        break;
      }
    }

    return FormScreenTemplate(
      title: roleTitle,
      actions: [
        // Audit A10: busy state on the manual refresh — an 18px spinner
        // replaces the button and re-trigger is refused via the
        // _isRefreshing guard in _refreshUserData until the fetch resolves.
        // NOTE for audit X-01: this 18px AppBar spinner intentionally stays
        // a raw CircularProgressIndicator — ThemedLoadingIndicator is a
        // centered full-size widget and cannot fit AppBar action bounds.
        _isRefreshing
            ? const Padding(
                key: ValueKey('kyc_refresh_busy'),
                padding: EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                key: const Key('kyc_refresh_button'),
                icon: const Icon(Icons.refresh),
                tooltip: l10n.tooltipRefreshStatus,
                onPressed: _refreshUserData,
              ),
      ],
      onRefresh: _refreshUserData,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile-refresh failure (audit A4): fetchUserProfile failures
          // are stored on the provider — surface them here with a retry
          // instead of rendering a stale KYC status with zero signal.
          // (Slot upload failures keep their own per-slot banners below;
          // uploadDocument never touches auth.error, so this banner reads
          // as refresh-only in practice.)
          if (auth.error != null) ...[
            ThemedErrorBanner(
              key: const Key('kyc_refresh_error_banner'),
              message: auth.error!,
              onRetry: _refreshUserData,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Stitch Status Banner
          _buildStatusBanner(
            displayStatus: displayStatus,
            isApproved: isApproved,
            isPending: isPending,
            isRejected: isRejected,
          ),

          if (isRejected &&
              user?.rejectionReason != null &&
              user!.rejectionReason!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildRejectionReasonBanner(l10n, user.rejectionReason!),
          ],

          if (isApproved) ...[
            const SizedBox(height: AppSpacing.md),
            _buildApprovedLockedBanner(),
          ],

          const SizedBox(height: AppSpacing.xl),

          // Section Header
          ThemedSectionHeader(
            title: context.l10n.requiredDocsHeader,
            subtitle: isOwner
                ? context.l10n.kycOwnerDocsSub
                : context.l10n.kycEmployeeDocsSub,
          ),
          const SizedBox(height: AppSpacing.lg),

          // Per-Document Upload Slots
          ...slots.map(
            (slot) => _buildDocumentSlotCard(
              slot: slot,
              user: user,
              isApproved: isApproved,
              isFirstIncomplete: slot['key'] == firstIncompleteKey,
            ),
          ),
        ],
      ),
    );
  }
}
