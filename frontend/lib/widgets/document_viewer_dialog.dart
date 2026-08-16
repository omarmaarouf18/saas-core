import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'themed_card.dart';
import 'themed_loading_indicator.dart';
import 'themed_error_banner.dart';
import 'status_badge.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_text_field.dart';

class DocumentViewerDialog extends StatefulWidget {
  final Map<String, dynamic> submission;
  final String initialDocType;
  final String? internalToken;
  final String? reviewerToken;

  const DocumentViewerDialog({
    super.key,
    required this.submission,
    this.initialDocType = 'id_front',
    this.internalToken,
    this.reviewerToken,
  });

  @override
  State<DocumentViewerDialog> createState() => _DocumentViewerDialogState();
}

class _DocumentViewerDialogState extends State<DocumentViewerDialog> {
  late String _selectedDocType;
  Uint8List? _bytes;
  bool _isLoading = false;
  String? _error;

  bool _isSubmittingReview = false;
  String? _reviewError;
  bool _showRejectForm = false;
  final TextEditingController _reasonController = TextEditingController();
  String? _reasonValidationError;

  @override
  void initState() {
    super.initState();
    _selectedDocType = widget.initialDocType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDocument();
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String? _getDocUrl(String docType) {
    switch (docType) {
      case 'id_front':
        return widget.submission['id_front_url'] as String?;
      case 'id_back':
        return widget.submission['id_back_url'] as String?;
      case 'selfie':
        return widget.submission['selfie_url'] as String?;
      case 'business_proof':
        return widget.submission['business_proof_url'] as String?;
      default:
        return null;
    }
  }

  Future<void> _loadDocument() async {
    final l10n = AppLocalizations.of(context)!;
    final url = _getDocUrl(_selectedDocType);
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _error = l10n.docNotProvided;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _bytes = null;
      });
    }

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final bytes = await auth.fetchDocumentBytes(
        url,
        internalToken: widget.internalToken,
        reviewerToken: widget.reviewerToken,
      );
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _isLoading = false;
          _error = l10n.docFailedLoad;
        });
      }
    }
  }

  void _onDocTypeChanged(String docType) {
    if (_selectedDocType == docType) return;
    setState(() {
      _selectedDocType = docType;
    });
    _loadDocument();
  }

  Future<void> _submitReview(String action, [String? reason]) async {
    setState(() {
      _isSubmittingReview = true;
      _reviewError = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final userId = widget.submission['user_id']?.toString() ?? '';
      final success = await auth.reviewSubmission(
        userId: userId,
        action: action,
        reason: reason,
        internalToken: widget.internalToken,
        reviewerToken: widget.reviewerToken,
      );

      if (success && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
          _reviewError = (e is ApiClientException) ? e.message : e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final username = widget.submission['username']?.toString() ?? 'User';
    final role = widget.submission['role']?.toString() ?? 'user';
    final status = widget.submission['kyc_status']?.toString() ??
        widget.submission['kye_status']?.toString() ??
        'pending';

    final url = _getDocUrl(_selectedDocType) ?? '';
    final isPdf = url.toLowerCase().contains('.pdf');

    return Dialog(
      key: const Key('document_viewer_dialog'),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.docViewerTitle,
                          style: AppTypography.headlineLgMobile.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '$username (${role.toUpperCase()})',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(status: status),
                  IconButton(
                    key: const Key('close_document_viewer'),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Document Selection Chips/Tabs
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    key: const Key('doc_tab_id_front'),
                    label: Text(l10n.docTabIdFront),
                    selected: _selectedDocType == 'id_front',
                    onSelected: (_) => _onDocTypeChanged('id_front'),
                  ),
                  ChoiceChip(
                    key: const Key('doc_tab_id_back'),
                    label: Text(l10n.docTabIdBack),
                    selected: _selectedDocType == 'id_back',
                    onSelected: (_) => _onDocTypeChanged('id_back'),
                  ),
                  ChoiceChip(
                    key: const Key('doc_tab_selfie'),
                    label: Text(l10n.docTabSelfie),
                    selected: _selectedDocType == 'selfie',
                    onSelected: (_) => _onDocTypeChanged('selfie'),
                  ),
                  if (role == 'owner')
                    ChoiceChip(
                      key: const Key('doc_tab_business_proof'),
                      label: Text(l10n.docTabBusinessProof),
                      selected: _selectedDocType == 'business_proof',
                      onSelected: (_) => _onDocTypeChanged('business_proof'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Main Viewer Container
              Expanded(
                child: ThemedCard(
                  padding: AppSpacing.md,
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        if (_isLoading) {
                          return ThemedLoadingIndicator(
                            key: const Key('document_loading_indicator'),
                            message: l10n.docLoadingPreview,
                          );
                        }
                        if (_error != null) {
                          return ThemedErrorBanner(
                            key: const Key('document_error_banner'),
                            message: _error!,
                            onRetry: _loadDocument,
                          );
                        }
                        if (_bytes != null) {
                          if (isPdf) {
                            return Container(
                              key: const Key('document_pdf_preview'),
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.picture_as_pdf,
                                      size: 48,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      l10n.docPdfPreviewTitle,
                                      style: AppTypography.titleMd.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      l10n.docFileSize(_bytes!.lengthInBytes),
                                      style: AppTypography.bodyMd.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Image.memory(
                            _bytes!,
                            key: const Key('document_image_preview'),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return ThemedErrorBanner(
                                key: const Key('document_error_banner'),
                                message: l10n.docDecodeError,
                              );
                            },
                          );
                        }
                        return Text(l10n.docNoDocument);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Error Banner for Review Submissions
              if (_reviewError != null) ...[
                ThemedErrorBanner(
                  key: const Key('document_review_error_banner'),
                  message: _reviewError!,
                  onRetry: () => setState(() => _reviewError = null),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],

              // Review Action Controls (Approve / Reject)
              if (_showRejectForm) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ThemedTextField(
                      key: const Key('rejection_reason_field'),
                      controller: _reasonController,
                      labelText: l10n.docRejectionReasonLabel,
                      hintText: l10n.docRejectionReasonHint,
                      maxLines: 2,
                    ),
                    if (_reasonValidationError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _reasonValidationError!,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            text: l10n.cancel,
                            onPressed: _isSubmittingReview
                                ? null
                                : () => setState(() {
                                      _showRejectForm = false;
                                      _reasonValidationError = null;
                                    }),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: PrimaryButton(
                            key: const Key('confirm_reject_button'),
                            text: l10n.docConfirmReject,
                            isLoading: _isSubmittingReview,
                            onPressed: () {
                              final text = _reasonController.text.trim();
                              if (text.isEmpty) {
                                setState(() {
                                  _reasonValidationError =
                                      l10n.docRejectionReasonReq;
                                });
                                return;
                              }
                              _submitReview('reject', text);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        key: const Key('reject_submission_button'),
                        text: l10n.kybKyeRejectBtn,
                        icon: Icons.cancel_outlined,
                        onPressed: _isSubmittingReview
                            ? null
                            : () => setState(() {
                                  _showRejectForm = true;
                                  _reasonValidationError = null;
                                }),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        key: const Key('approve_submission_button'),
                        text: l10n.kybKyeApproveBtn,
                        icon: Icons.check_circle_outline,
                        isLoading: _isSubmittingReview,
                        onPressed: () => _submitReview('approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
