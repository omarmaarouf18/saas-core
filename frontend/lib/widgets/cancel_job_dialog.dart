import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import 'primary_button.dart';
import 'secondary_button.dart';
import 'themed_error_banner.dart';
import 'themed_text_field.dart';

class CancelJobDialog extends StatefulWidget {
  final String jobId;
  final Future<void> Function(String reason) onConfirm;

  /// Optional request-flow copy overrides (ADR-0027): when set, the dialog
  /// presents itself as a cancellation REQUEST subject to owner approval
  /// rather than an immediate cancellation. Null (default) keeps the
  /// legacy immediate-cancel copy used by the owner/customer paths.
  final String? titleText;
  final String? bodyText;
  final String? confirmText;

  const CancelJobDialog({
    super.key,
    required this.jobId,
    required this.onConfirm,
    this.titleText,
    this.bodyText,
    this.confirmText,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String jobId,
    required Future<void> Function(String reason) onConfirm,
    String? titleText,
    String? bodyText,
    String? confirmText,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CancelJobDialog(
        jobId: jobId,
        onConfirm: onConfirm,
        titleText: titleText,
        bodyText: bodyText,
        confirmText: confirmText,
      ),
    );
  }

  @override
  State<CancelJobDialog> createState() => _CancelJobDialogState();
}

class _CancelJobDialogState extends State<CancelJobDialog> {
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isReasonEmpty = _reasonController.text.trim().isEmpty;

    return AlertDialog(
      title: Text(widget.titleText ?? l10n.cancelJobHeader(widget.jobId)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bodyText ?? l10n.cancelReasonRequiredLong,
              style: AppTypography.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ThemedTextField(
              key: const Key('cancel_reason_input'),
              controller: _reasonController,
              labelText: l10n.cancelJobReasonLabel,
              hintText: l10n.cancelJobReasonHint,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ThemedErrorBanner(
                message: _inlineError!,
              ),
            ],
          ],
        ),
      ),
      actions: [
        SecondaryButton(
          text: l10n.cancelJobKeep,
          isFullWidth: false,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          key: const Key('confirm_cancel_button'),
          text: widget.confirmText ?? l10n.cancelJobConfirm,
          isFullWidth: false,
          isDestructive: true,
          isLoading: _isSubmitting,
          onPressed: (isReasonEmpty || _isSubmitting)
              ? null
              : () async {
                  setState(() {
                    _isSubmitting = true;
                    _inlineError = null;
                  });
                  try {
                    await widget.onConfirm(_reasonController.text.trim());
                    if (context.mounted) {
                      Navigator.of(context).pop(true);
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _isSubmitting = false;
                        _inlineError = friendlyErrorMessage(e);
                      });
                    }
                  }
                },
        ),
      ],
    );
  }
}
