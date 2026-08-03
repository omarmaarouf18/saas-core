import 'package:flutter/material.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';

class CancelJobDialog extends StatefulWidget {
  final String jobId;
  final Future<void> Function(String reason) onConfirm;

  const CancelJobDialog({
    super.key,
    required this.jobId,
    required this.onConfirm,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String jobId,
    required Future<void> Function(String reason) onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CancelJobDialog(
        jobId: jobId,
        onConfirm: onConfirm,
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
    final isReasonEmpty = _reasonController.text.trim().isEmpty;

    return AlertDialog(
      title: Text("Cancel Job #${widget.jobId}"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Please provide a reason for cancelling this job. A valid cancellation reason is required.",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('cancel_reason_input'),
              controller: _reasonController,
              autofocus: true,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: "Cancellation Reason *",
                hintText: "e.g. Customer requested cancellation / Change of plans",
                border: OutlineInputBorder(),
              ),
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: 12),
              Text(
                _inlineError!,
                style: const TextStyle(color: AppColors.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text("Keep Job"),
        ),
        ElevatedButton(
          key: const Key('confirm_cancel_button'),
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text("Confirm Cancel"),
        ),
      ],
    );
  }
}
