import 'package:flutter/material.dart';

import '../../../core/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../ui/qd_ui.dart';
import '../customer_theme.dart';

/// Cancel-order reason sheet. The reason is required (the provider and the
/// server reject an empty one); the confirm button stays disabled until
/// something is typed. [onConfirm] runs the existing `cancelJob`; a failure
/// keeps the sheet open with the error, like the old CancelJobDialog.
/// Returns true when the order was cancelled.
class CancelOrderSheet extends StatefulWidget {
  const CancelOrderSheet({super.key, required this.onConfirm});

  final Future<void> Function(String reason) onConfirm;

  static Future<bool?> show(BuildContext context,
      {required Future<void> Function(String reason) onConfirm}) {
    final c = QdColors.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Like the old dialog: typed text is never lost to an outside tap.
      isDismissible: false,
      enableDrag: false,
      backgroundColor: c.surface,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      builder: (ctx) => CustomerTheme(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: CancelOrderSheet(onConfirm: onConfirm),
        ),
      ),
    );
  }

  @override
  State<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends State<CancelOrderSheet> {
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onConfirm(reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final empty = _reason.text.trim().isEmpty;
    return QdBottomSheet(
      key: const Key('ord_cancel_sheet'),
      title: l10n.ordCancelSheetTitle,
      subtitle: l10n.ordCancelSheetBody,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdTextField(
              key: const Key('ord_cancel_reason_input'),
              label: l10n.ordCancelReasonLabel,
              controller: _reason,
              maxLines: 3,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('ord_cancel_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            QdButton.destructive(
              key: const Key('ord_cancel_confirm'),
              label: l10n.ordCancelOrder,
              fullWidth: true,
              loading: _submitting,
              onPressed: empty ? null : _confirm,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('ord_cancel_keep'),
              label: l10n.ordCancelKeep,
              fullWidth: true,
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
