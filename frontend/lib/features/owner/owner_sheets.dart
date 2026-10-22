import 'package:flutter/material.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';

/// Sheets and notices shared by the redesigned owner pages (FE-OWNER-1).
/// Sheets open in the root navigator's overlay, outside the page's theme
/// and providers, so each one is wrapped in [QdThemeScope] and gets what
/// it needs through its constructor.

/// A SnackBar notice, with a retry action when [onRetry] is given.
void showOwnerNotice(BuildContext context, String message,
    {VoidCallback? onRetry}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: onRetry == null
          ? null
          : SnackBarAction(label: context.l10n.retry, onPressed: onRetry),
    ));
}

Future<T?> showOwnerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final c = QdColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
    ),
    builder: (ctx) => QdThemeScope(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// "Are you sure?" sheet. Returns true when confirmed. The action itself
/// runs on the page afterwards, so a failure is reported there.
Future<bool> showOwnerConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  Key? key,
}) async {
  final l10n = context.l10n;
  final res = await showOwnerSheet<bool>(
    context,
    builder: (ctx) => QdBottomSheet(
      key: key ?? const Key('own_confirm_sheet'),
      title: title,
      subtitle: message,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: QdSpace.x2),
          if (destructive)
            QdButton.destructive(
              key: const Key('own_confirm_yes'),
              label: confirmLabel,
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            )
          else
            QdButton(
              key: const Key('own_confirm_yes'),
              label: confirmLabel,
              fullWidth: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          const SizedBox(height: QdSpace.x1),
          QdButton.text(
            key: const Key('own_confirm_no'),
            label: l10n.ownNotNow,
            fullWidth: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    ),
  );
  return res == true;
}

/// Owner cancel with a required reason (the provider and the server reject
/// an empty one). Like the old CancelJobDialog: not dismissible by an
/// outside tap or drag, and a failure keeps the sheet open with the error.
/// Returns true when the order was cancelled.
class OwnerCancelOrderSheet extends StatefulWidget {
  const OwnerCancelOrderSheet(
      {super.key, required this.body, required this.onConfirm});

  final String body;
  final Future<void> Function(String reason) onConfirm;

  static Future<bool?> show(BuildContext context,
          {required String body,
          required Future<void> Function(String reason) onConfirm}) =>
      showOwnerSheet<bool>(
        context,
        dismissible: false,
        builder: (_) => OwnerCancelOrderSheet(body: body, onConfirm: onConfirm),
      );

  @override
  State<OwnerCancelOrderSheet> createState() => _OwnerCancelOrderSheetState();
}

class _OwnerCancelOrderSheetState extends State<OwnerCancelOrderSheet> {
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
      key: const Key('own_cancel_sheet'),
      title: l10n.ownCancelSheetTitle,
      subtitle: widget.body,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdTextField(
              key: const Key('own_cancel_reason'),
              label: l10n.ownCancelReasonLabel,
              controller: _reason,
              maxLines: 3,
              enabled: !_submitting,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('own_cancel_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            QdButton.destructive(
              key: const Key('own_cancel_confirm'),
              label: l10n.ownCancelOrder,
              fullWidth: true,
              loading: _submitting,
              onPressed: empty ? null : _confirm,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('own_cancel_keep'),
              label: l10n.ownCancelKeep,
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
