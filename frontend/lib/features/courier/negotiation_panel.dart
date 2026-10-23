import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import '../customer/order/order_view.dart'
    show
        CounterOfferError,
        counterOfferBounds,
        isProposalWindowOver,
        kPriceProposalWindow,
        validateCounterOffer;
import 'courier_controller.dart';
import 'courier_format.dart';
import 'courier_sheets.dart';
import 'courier_widgets.dart';

/// Who holds the open fare proposal, from the courier's side.
enum CourierProposal { none, mine, customer }

CourierProposal courierProposalOf(Job job) {
  if (job.proposedPrice == null) return CourierProposal.none;
  return job.proposedBy?.trim().toLowerCase() == 'employee'
      ? CourierProposal.mine
      : CourierProposal.customer;
}

/// Fare negotiation for an `awaiting_price_response` job (ADR-0006,
/// one-shot), the courier side of the customer's A-Negotiate view; the
/// bounds and checks are the customer's (`counterOfferBounds`,
/// `validateCounterOffer`: 0.5×–1.5× the suggested price, the server's
/// rule). Three cases, as on the old card:
/// - nobody proposed and there is a suggested price: propose a fare;
/// - the customer proposed: accept (confirmed first: the trip starts at
///   that price) or decline;
/// - the courier proposed: waiting for the customer.
///
/// Errors as before: a 429 lockout shows the server's text with no retry
/// and no refetch; on propose, 400 / 409 refetch first and then say
/// whether the customer's proposal landed first (no retry), the job moved
/// on, or the price is out of range; on respond, 409 says the order changed
/// and 400 / 429 show the server's text, with a refetch on 400 / 409. Other
/// failures offer a retry. Answers are disabled once the window is over.
class CourierNegotiationPanel extends StatefulWidget {
  const CourierNegotiationPanel({super.key, required this.job});

  final Job job;

  @override
  State<CourierNegotiationPanel> createState() =>
      _CourierNegotiationPanelState();
}

class _CourierNegotiationPanelState extends State<CourierNegotiationPanel> {
  final _price = TextEditingController();
  bool _busy = false;
  String? _inputError;

  /// Server failure shown in the panel.
  String? _error;
  VoidCallback? _retry;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _fail(String message, {VoidCallback? retry}) {
    setState(() {
      _error = message;
      _retry = retry;
    });
  }

  Future<void> _propose(double suggested) async {
    if (_busy) return;
    final l10n = context.l10n;
    final b = counterOfferBounds(suggested);
    final check = validateCounterOffer(_price.text, suggested);
    if (check != null) {
      setState(() => _inputError = check == CounterOfferError.notANumber
          ? l10n.ordPriceInvalid
          : l10n.ordPriceOutOfRange(
              formatMoney(l10n, b.min), formatMoney(l10n, b.max)));
      return;
    }
    final value = double.parse(_price.text.trim());
    final ctl = context.read<CourierController>();
    final jobId = widget.job.id;
    setState(() {
      _busy = true;
      _inputError = null;
      _error = null;
    });
    try {
      await ctl.proposePrice(widget.job, value);
      _price.clear();
      if (mounted) showCourierNotice(context, l10n.courProposalSent);
    } catch (e) {
      if (!mounted) return;
      final status = e is ApiClientException ? e.statusCode : null;
      if (status == 429 && e is ApiClientException) {
        // Re-tapping extends the lockout: no retry, no refetch.
        _fail(e.message);
      } else if (status == 400 || status == 409) {
        // Converge on the server first, then pick the copy from the fresh
        // job (never from the error text).
        await ctl.reload();
        if (!mounted) return;
        final fresh = ctl.jobs.where((j) => j.id == jobId).firstOrNull;
        if (fresh != null &&
            courierProposalOf(fresh) == CourierProposal.customer) {
          _fail(l10n.employeeProposalRacedError);
        } else if (fresh == null ||
            fresh.status.trim().toLowerCase() != 'awaiting_price_response') {
          _fail(l10n.ordStateChanged);
        } else {
          _fail(
              l10n.ordPriceOutOfRange(
                  formatMoney(l10n, b.min), formatMoney(l10n, b.max)),
              retry: () => _propose(suggested));
        }
      } else {
        if (status == 404) await ctl.reload();
        if (mounted) {
          _fail(friendlyErrorMessage(e), retry: () => _propose(suggested));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(String decision) async {
    if (_busy) return;
    final ctl = context.read<CourierController>();
    if (isProposalWindowOver(widget.job, ctl.now())) return;
    final l10n = context.l10n;
    if (decision == 'accept') {
      final price = widget.job.proposedPrice;
      final ok = await confirmAcceptPrice(
          context, price == null ? '' : formatMoney(l10n, price));
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ctl.respondPrice(widget.job, decision);
      if (mounted) {
        showCourierNotice(
            context,
            decision == 'accept'
                ? l10n.courPriceAccepted
                : l10n.courPriceDeclined);
      }
    } catch (e) {
      if (!mounted) return;
      final status = e is ApiClientException ? e.statusCode : null;
      final String message;
      if (status == 409) {
        message = l10n.ordStateChanged;
      } else if ((status == 429 || status == 400) && e is ApiClientException) {
        message = e.message;
      } else {
        message = friendlyErrorMessage(e);
      }
      _fail(message,
          retry: status == 429 ? null : () => _respondAgain(decision));
      if (status == 409 || status == 400) await ctl.reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A retry skips the accept confirmation (already confirmed).
  Future<void> _respondAgain(String decision) async {
    if (_busy) return;
    final ctl = context.read<CourierController>();
    if (isProposalWindowOver(widget.job, ctl.now())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ctl.respondPrice(widget.job, decision);
    } catch (e) {
      if (mounted) {
        final status = e is ApiClientException ? e.statusCode : null;
        _fail(courierFailure(context, e),
            retry: status == 429 ? null : () => _respondAgain(decision));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _expired() {
    if (!mounted) return;
    setState(() {});
    context.read<CourierController>().reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<CourierController>();
    final job = widget.job;
    final party = courierProposalOf(job);
    final suggested = job.suggestedPrice ?? 0;
    final proposed = job.proposedPrice;
    final expires = job.priceProposalExpiresAt;
    final over = isProposalWindowOver(job, ctl.now());
    final b = counterOfferBounds(suggested);

    final (String title, String? body) = switch (party) {
      CourierProposal.customer => (
          l10n.courPriceCustomerTitle(formatMoney(l10n, proposed!)),
          suggested > 0
              ? l10n.courPriceWas(formatMoney(l10n, suggested))
              : null,
        ),
      CourierProposal.mine => (
          l10n.courPriceMineTitle(formatMoney(l10n, proposed!)),
          l10n.courPriceMineBody,
        ),
      CourierProposal.none when suggested > 0 => (
          l10n.courPriceProposeTitle,
          l10n.courPriceProposeBody(formatMoney(l10n, suggested)),
        ),
      CourierProposal.none => (l10n.courPriceWaitingTitle, null),
    };

    return Container(
      key: Key('courier_negotiation_${party.name}'),
      padding: const EdgeInsets.all(QdSpace.x4),
      decoration: BoxDecoration(
        color: c.fillSubtle,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(QdRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: QdText.rowTitle.copyWith(color: c.textPrimary)),
          if (body != null) ...[
            const SizedBox(height: QdSpace.x1),
            Text(body,
                style: QdText.secondary.copyWith(color: c.textSecondary)),
          ],
          if (party == CourierProposal.none && suggested > 0) ...[
            const SizedBox(height: QdSpace.x3),
            QdTextField(
              key: const Key('courier_propose_input'),
              label: l10n.courPriceProposeLabel,
              controller: _price,
              ltr: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              helperText: l10n.courPriceBounds(
                  formatMoney(l10n, b.min), formatMoney(l10n, b.max)),
              errorText: _inputError,
              enabled: !_busy && !over,
            ),
            const SizedBox(height: QdSpace.x3),
            QdButton(
              key: const Key('courier_propose_send'),
              label: l10n.ordSendOffer,
              fullWidth: true,
              loading: _busy,
              onPressed: over ? null : () => _propose(suggested),
            ),
          ],
          if (expires != null) ...[
            const SizedBox(height: QdSpace.x3),
            QdCountdown(
              key: const Key('courier_price_countdown'),
              expiresAt: expires,
              total: kPriceProposalWindow,
              style: QdCountdownStyle.bar,
              label: l10n.ordOfferExpiresIn,
              now: ctl.now,
              onExpired: _expired,
            ),
          ],
          if (over) ...[
            const SizedBox(height: QdSpace.x2),
            Text(l10n.courPriceExpired,
                key: const Key('courier_price_expired'),
                style: QdText.secondary.copyWith(color: c.danger)),
          ],
          if (_error != null) ...[
            const SizedBox(height: QdSpace.x3),
            QdBanner(
              key: const Key('courier_price_error'),
              tone: QdBannerTone.danger,
              icon: Icons.error_outline,
              message: _error!,
              actionLabel: _retry == null ? null : l10n.retry,
              onAction: _retry,
            ),
          ],
          if (party == CourierProposal.customer) ...[
            // Stacked full width: the labels carry the amount and do not
            // fit side by side at 360 dp.
            const SizedBox(height: QdSpace.x3),
            QdButton(
              key: const Key('courier_price_accept'),
              label: l10n.ordAcceptPrice(formatMoney(l10n, proposed!)),
              fullWidth: true,
              loading: _busy,
              onPressed: over ? null : () => _respond('accept'),
            ),
            const SizedBox(height: QdSpace.x2),
            QdButton.secondary(
              key: const Key('courier_price_decline'),
              label: l10n.ordDecline,
              fullWidth: true,
              onPressed: _busy || over ? null : () => _respond('decline'),
            ),
          ],
        ],
      ),
    );
  }
}
