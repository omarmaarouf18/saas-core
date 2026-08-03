import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'themed_card.dart';
import 'themed_loading_indicator.dart';
import 'themed_error_banner.dart';
import 'status_badge.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedDocType = widget.initialDocType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDocument();
    });
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
    final url = _getDocUrl(_selectedDocType);
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _error = 'Document not provided for this submission.';
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
          _error = 'Failed to load document preview';
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

  @override
  Widget build(BuildContext context) {
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
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                          'Document Viewer',
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
                    tooltip: 'Close',
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
                    label: const Text('Front ID'),
                    selected: _selectedDocType == 'id_front',
                    onSelected: (_) => _onDocTypeChanged('id_front'),
                  ),
                  ChoiceChip(
                    key: const Key('doc_tab_id_back'),
                    label: const Text('Back ID'),
                    selected: _selectedDocType == 'id_back',
                    onSelected: (_) => _onDocTypeChanged('id_back'),
                  ),
                  ChoiceChip(
                    key: const Key('doc_tab_selfie'),
                    label: const Text('Selfie'),
                    selected: _selectedDocType == 'selfie',
                    onSelected: (_) => _onDocTypeChanged('selfie'),
                  ),
                  if (role == 'owner')
                    ChoiceChip(
                      key: const Key('doc_tab_business_proof'),
                      label: const Text('Business Proof'),
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
                          return const ThemedLoadingIndicator(
                            key: Key('document_loading_indicator'),
                            message: 'Loading document preview...',
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
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.picture_as_pdf,
                                    size: 64,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'PDF Document Preview',
                                    style: AppTypography.titleMd.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'File Size: ${_bytes!.lengthInBytes} bytes',
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Image.memory(
                            _bytes!,
                            key: const Key('document_image_preview'),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const ThemedErrorBanner(
                                key: Key('document_error_banner'),
                                message: 'Failed to decode image bytes.',
                              );
                            },
                          );
                        }
                        return const Text('No document loaded.');
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
