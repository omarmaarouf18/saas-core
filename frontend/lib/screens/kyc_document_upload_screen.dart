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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshUserData();
    });
  }

  Future<void> _refreshUserData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.fetchUserProfile();
  }

  /// Consolidated bottom sheet picker for camera, gallery, and optional PDF selection.
  Future<String?> _showSourcePickerBottomSheet(
    BuildContext context, {
    required bool allowPdf,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allowPdf ? "Select File Source" : "Select Image Source",
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: Text(l10n.kycTakeCamera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: Text(l10n.kycChooseGallery),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (allowPdf)
              ListTile(
                leading:
                    const Icon(Icons.picture_as_pdf, color: AppColors.primary),
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
      final xfile = await picker.pickImage(source: ImageSource.camera);
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        return PickedDocumentFile(filename: xfile.name, bytes: bytes);
      }
    } else if (source == 'gallery') {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
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
      setState(() {
        _slotErrors[slotKey] =
            "File size exceeds maximum allowed size of 10MB (${(pickedFile.bytes.length / (1024 * 1024)).toStringAsFixed(1)}MB).";
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
            ? "Invalid file format. Only JPEG, PNG, and PDF files are allowed for $slotTitle."
            : "Invalid file format. Only JPEG and PNG image files are allowed for $slotTitle.";
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
    return ThemedCard(
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Verification Status",
                style: AppTypography.titleMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              StatusBadge(status: displayStatus),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isApproved
                ? "Your account verification has been approved by administrators. Your account is fully active."
                : (isPending
                    ? "All required documents have been uploaded and are pending super admin review."
                    : (isRejected
                        ? "Your document submission was rejected. Please review the reason below and re-upload the corrected document(s)."
                        : "Please upload all required verification documents below to enable account capabilities.")),
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectionReasonBanner(AppLocalizations l10n, String reason) {
    return ThemedErrorBanner(
      message: l10n.rejectionReasonMessage(reason),
      onRetry: _refreshUserData,
    );
  }

  Widget _buildApprovedLockedBanner() {
    return const ThemedSuccessBanner(
      message: "Documents are locked because your account is approved.",
    );
  }

  Widget _buildDocumentSlotCard({
    required Map<String, dynamic> slot,
    required UserProfile? user,
    required bool isApproved,
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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isUploaded
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smBorder,
                  ),
                  child: Icon(
                    icon,
                    color: isUploaded ? AppColors.success : AppColors.primary,
                    size: 28,
                  ),
                ),
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
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
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
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: AppRadius.smBorder,
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
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
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.image,
                                    size: 40,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            else if (allowPdf ||
                                (localPicked?.filename
                                        .toLowerCase()
                                        .endsWith('.pdf') ??
                                    false))
                              const Icon(
                                Icons.picture_as_pdf,
                                size: 40,
                                color: AppColors.error,
                              )
                            else
                              const Icon(
                                Icons.insert_drive_file,
                                size: 40,
                                color: AppColors.primary,
                              ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                localPicked != null
                                    ? localPicked.filename
                                    : "Document on file (${existingPath!.split('/').last})",
                                style: AppTypography.bodyMd.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isApproved)
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                color: AppColors.error,
                                tooltip: "Remove selection",
                                onPressed: isUploading
                                    ? null
                                    : () {
                                        setState(() {
                                          _pickedFiles.remove(slotKey);
                                        });
                                      },
                              ),
                          ],
                        ),
                      ),
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
                          text: "Replace Document",
                          icon: Icons.refresh,
                          isLoading: isUploading,
                          onPressed: isUploading
                              ? null
                              : () =>
                                  _handleSlotUpload(slotKey, title, allowPdf),
                        )
                      : PrimaryButton(
                          key: ValueKey('btn_upload_$slotKey'),
                          text: "Upload Document",
                          icon: Icons.upload_file,
                          isLoading: isUploading,
                          onPressed: isUploading
                              ? null
                              : () =>
                                  _handleSlotUpload(slotKey, title, allowPdf),
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
    final roleTitle =
        isOwner ? 'Owner Verification (KYB)' : 'Employee Verification (KYE)';

    final status = user?.effectiveKycStatus ?? '';
    final displayStatus = status.isEmpty ? 'unverified' : status;

    final isApproved = user?.isApproved ?? false;
    final isRejected = user?.isRejected ?? false;
    final isPending = user?.isPendingApproval ?? false;

    // Define required slots based on role
    final slots = [
      {
        'key': 'id_front',
        'title': 'ID Card (Front)',
        'subtitle':
            'Clear photo of the front side of your National ID or Passport.',
        'allowPdf': false,
        'icon': Icons.badge_outlined,
      },
      {
        'key': 'id_back',
        'title': 'ID Card (Back)',
        'subtitle': 'Clear photo of the back side of your National ID.',
        'allowPdf': false,
        'icon': Icons.flip_to_back_outlined,
      },
      {
        'key': 'selfie',
        'title': 'Selfie Photo',
        'subtitle': 'Selfie holding your ID card next to your face.',
        'allowPdf': false,
        'icon': Icons.account_box_outlined,
      },
      if (isOwner)
        {
          'key': 'business_proof',
          'title': 'Business Proof / Commercial Register',
          'subtitle':
              'Official commercial register or tax registration document (PDF, JPEG, or PNG).',
          'allowPdf': true,
          'icon': Icons.business_outlined,
        },
    ];

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(roleTitle),
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.tooltipRefreshStatus,
            onPressed: _refreshUserData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Header Card
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
                title: "Required Verification Documents",
                subtitle: isOwner
                    ? "Owners must upload all 4 documents (ID Front, ID Back, Selfie, Business Proof)."
                    : "Employees must upload all 3 documents (ID Front, ID Back, Selfie).",
              ),
              const SizedBox(height: AppSpacing.lg),

              // Per-Document Upload Slots
              ...slots.map(
                (slot) => _buildDocumentSlotCard(
                  slot: slot,
                  user: user,
                  isApproved: isApproved,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
