import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import 'courier_format.dart';

/// Courier sheets (FE-COURIER). Like the old dialogs, typed input is never
/// lost to an outside tap or a drag; a failure keeps the sheet open with
/// the error. Each returns true when its action went through.

Future<bool?> _showSheet(BuildContext context, WidgetBuilder builder) {
  final c = QdColors.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Builder(builder: builder),
    ),
  );
}

/// The message for a failed action: 409 says the order changed (the other
/// side acted or the status moved on), anything else the friendly copy.
String courierFailure(BuildContext context, Object e) =>
    e is ApiClientException && e.statusCode == 409
        ? context.l10n.ordStateChanged
        : friendlyErrorMessage(e);

/// "Delivered" confirmation. Cash orders confirm the cash was collected
/// (`cash_collected: true`, which the server requires for cash orders) and
/// may give the amount actually collected when it differs from the price
/// (`actual_cash_amount`); other orders confirm the delivery only.
class CourierCompleteSheet extends StatefulWidget {
  const CourierCompleteSheet(
      {super.key, required this.job, required this.onConfirm});

  final Job job;

  /// Runs the completion with the different amount, or null for the price.
  final Future<void> Function(double? actualAmount) onConfirm;

  static Future<bool?> show(BuildContext context,
          {required Job job,
          required Future<void> Function(double? actualAmount) onConfirm}) =>
      _showSheet(
          context, (_) => CourierCompleteSheet(job: job, onConfirm: onConfirm));

  @override
  State<CourierCompleteSheet> createState() => _CourierCompleteSheetState();
}

class _CourierCompleteSheetState extends State<CourierCompleteSheet> {
  final _amount = TextEditingController();
  bool _different = false;
  bool _busy = false;
  String? _inputError;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    double? actual;
    if (_different) {
      actual = double.tryParse(_amount.text.trim());
      if (actual == null || actual <= 0) {
        setState(() => _inputError = context.l10n.courAmountInvalid);
        return;
      }
    }
    setState(() {
      _busy = true;
      _inputError = null;
      _error = null;
    });
    try {
      await widget.onConfirm(actual);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = courierFailure(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final job = widget.job;
    final cod = isCod(job);
    final price = priceOf(job);
    final amount = price == null ? null : formatMoney(l10n, price);

    return QdBottomSheet(
      key: const Key('courier_complete_sheet'),
      title: l10n.courCompleteTitle,
      subtitle: cod
          ? (amount == null
              ? l10n.courCompleteCodNoPrice
              : l10n.courCompleteCod(amount))
          : l10n.courCompleteNonCod,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cod) ...[
              if (!_different)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: QdButton.text(
                    key: const Key('courier_complete_different'),
                    label: l10n.courCompleteDifferent,
                    small: true,
                    onPressed:
                        _busy ? null : () => setState(() => _different = true),
                  ),
                )
              else
                QdTextField(
                  key: const Key('courier_complete_amount'),
                  label: l10n.courCompleteAmountLabel,
                  controller: _amount,
                  ltr: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  errorText: _inputError,
                  helperText: l10n.courCompleteAmountHelp,
                  enabled: !_busy,
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('courier_complete_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            QdButton(
              key: const Key('courier_complete_confirm'),
              label: cod
                  ? (amount == null || _different
                      ? l10n.courCompleteConfirmCash
                      : l10n.courCompleteConfirmAmount(amount))
                  : l10n.courCompleteConfirm,
              fullWidth: true,
              loading: _busy,
              onPressed: _confirm,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('courier_complete_cancel'),
              label: l10n.courNotYet,
              fullWidth: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
            Text(l10n.courCompleteNote,
                textAlign: TextAlign.center,
                style: QdText.caption.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Cancellation request (ADR-0027): the reason goes to the company owner,
/// who approves or rejects it; the job stays the courier's until then.
class CourierCancelRequestSheet extends StatefulWidget {
  const CourierCancelRequestSheet({super.key, required this.onConfirm});

  final Future<void> Function(String reason) onConfirm;

  static Future<bool?> show(BuildContext context,
          {required Future<void> Function(String reason) onConfirm}) =>
      _showSheet(
          context, (_) => CourierCancelRequestSheet(onConfirm: onConfirm));

  @override
  State<CourierCancelRequestSheet> createState() =>
      _CourierCancelRequestSheetState();
}

class _CourierCancelRequestSheetState extends State<CourierCancelRequestSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = courierFailure(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final empty = _reason.text.trim().isEmpty;
    return QdBottomSheet(
      key: const Key('courier_cancel_sheet'),
      title: l10n.courCancelTitle,
      subtitle: l10n.courCancelBody,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QdTextField(
              key: const Key('courier_cancel_reason'),
              label: l10n.ordCancelReasonLabel,
              controller: _reason,
              maxLines: 3,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: QdSpace.x3),
              QdBanner(
                key: const Key('courier_cancel_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
            ],
            const SizedBox(height: QdSpace.x5),
            QdButton.destructive(
              key: const Key('courier_cancel_confirm'),
              label: l10n.courCancelSend,
              fullWidth: true,
              loading: _busy,
              onPressed: empty ? null : _confirm,
            ),
            const SizedBox(height: QdSpace.x1),
            QdButton.text(
              key: const Key('courier_cancel_keep'),
              label: l10n.courCancelKeep,
              fullWidth: true,
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accepting the customer's fare starts the trip at that price (the old
/// screen asked the same through a confirm dialog). True when confirmed.
Future<bool> confirmAcceptPrice(BuildContext context, String price) async {
  final l10n = context.l10n;
  final ok = await _showSheet(
    context,
    (ctx) => QdBottomSheet(
      key: const Key('courier_price_confirm_sheet'),
      title: l10n.courPriceAcceptTitle(price),
      subtitle: l10n.courPriceAcceptBody,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QdButton(
            key: const Key('courier_price_confirm'),
            label: l10n.ordAcceptPrice(price),
            fullWidth: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
          const SizedBox(height: QdSpace.x1),
          QdButton.text(
            key: const Key('courier_price_confirm_cancel'),
            label: l10n.courNotYet,
            fullWidth: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}
