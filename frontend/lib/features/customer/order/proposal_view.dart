import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import '../customer_format.dart';
import 'order_controller.dart';
import 'order_sections.dart';
import 'order_view.dart';

/// awaiting_price_response (A-Negotiate). Three cases, as in the old
/// negotiation card:
/// - the courier proposed: original vs proposed price, the difference, a
///   countdown, accept / decline (`respondPrice`);
/// - the customer proposed: the same comparison, "waiting for the courier";
/// - nobody proposed yet: a counter-offer within 0.5×–1.5× the suggested
///   price (`proposePrice`).
/// A 409 says the order changed; any other error (400, 429, network) shows
/// the friendly message. Every failure offers a retry and refetches, like
/// before. When the countdown ends the page switches to the cancelled view.
class OrderProposalView extends StatefulWidget {
  const OrderProposalView({super.key, required this.job});

  final Job job;

  @override
  State<OrderProposalView> createState() => _OrderProposalViewState();
}

class _OrderProposalViewState extends State<OrderProposalView> {
  final _price = TextEditingController();
  bool _busy = false;
  String? _inputError;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  String _failure(Object e) => e is ApiClientException && e.statusCode == 409
      ? context.l10n.ordStateChanged
      : friendlyErrorMessage(e);

  Future<void> _respond(String decision) async {
    if (_busy) return;
    final l10n = context.l10n;
    final ctl = context.read<OrderController>();
    setState(() => _busy = true);
    try {
      await ctl.respondPrice(decision);
      if (mounted) {
        showOrderNotice(context,
            decision == 'accept' ? l10n.ordAccepted : l10n.ordDeclined);
      }
    } catch (e) {
      if (mounted) {
        showOrderNotice(context, _failure(e),
            onRetry: () => _respond(decision));
      }
      await ctl.refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOffer(double suggested) async {
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
    final ctl = context.read<OrderController>();
    setState(() {
      _inputError = null;
      _busy = true;
    });
    try {
      await ctl.proposePrice(value);
      _price.clear();
      if (mounted) showOrderNotice(context, l10n.ordOfferSent);
    } catch (e) {
      if (mounted) {
        showOrderNotice(context, _failure(e),
            onRetry: () => _sendOffer(suggested));
      }
      await ctl.refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final job = widget.job;
    final ctl = context.watch<OrderController>();
    final party = proposalParty(job);
    final suggested = job.suggestedPrice ?? 0;
    final proposed = job.proposedPrice;
    final name = ctl.courierName;
    final expires = job.priceProposalExpiresAt;

    final (String title, String sub) = switch (party) {
      ProposalParty.courier => (
          name == null
              ? l10n.ordProposalCourierTitleNoName
              : l10n.ordProposalCourierTitle(name),
          l10n.ordProposalCourierSub,
        ),
      ProposalParty.customer => (
          l10n.ordProposalMineTitle(formatMoney(l10n, proposed!)),
          l10n.ordProposalMineSub,
        ),
      ProposalParty.none => (
          l10n.ordProposalOpenTitle,
          l10n.ordProposalOpenSub,
        ),
    };

    final Widget? footer = switch (party) {
      ProposalParty.courier => Row(
          children: [
            Expanded(
              child: QdButton.secondary(
                key: const Key('ord_decline'),
                label: l10n.ordDecline,
                fullWidth: true,
                onPressed: _busy ? null : () => _respond('decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: QdButton(
                key: const Key('ord_accept'),
                label: l10n.ordAcceptPrice(formatMoney(l10n, proposed!)),
                fullWidth: true,
                loading: _busy,
                onPressed: () => _respond('accept'),
              ),
            ),
          ],
        ),
      ProposalParty.none => QdButton(
          key: const Key('ord_send_offer'),
          label: l10n.ordSendOffer,
          fullWidth: true,
          loading: _busy,
          onPressed: () => _sendOffer(suggested),
        ),
      ProposalParty.customer => null,
    };

    return OrderLayout(
      key: const Key('ord_view_proposal'),
      footer: footer,
      children: [
        _ProposalHeader(name: name, title: title, subtitle: sub),
        const SizedBox(height: QdSpace.x5),
        if (proposed != null) ...[
          _PriceComparison(original: suggested, proposed: proposed),
          const SizedBox(height: QdSpace.x5),
        ] else ...[
          _CounterOffer(
            controller: _price,
            suggested: suggested,
            error: _inputError,
            enabled: !_busy,
            onSubmit: () => _sendOffer(suggested),
          ),
          const SizedBox(height: QdSpace.x5),
        ],
        if (expires != null) ...[
          QdCountdown(
            key: const Key('ord_countdown'),
            expiresAt: expires,
            total: kPriceProposalWindow,
            style: QdCountdownStyle.bar,
            label: l10n.ordOfferExpiresIn,
            now: ctl.now,
            onExpired: ctl.proposalExpired,
          ),
          const SizedBox(height: QdSpace.x2),
        ],
        Text(l10n.ordOfferExpiryNote,
            style: QdText.secondary
                .copyWith(color: QdColors.of(context).textSecondary)),
        const SizedBox(height: QdSpace.x5),
        OrderRouteCard(job: job, showPrice: false),
      ],
    );
  }
}

class _ProposalHeader extends StatelessWidget {
  const _ProposalHeader(
      {required this.name, required this.title, required this.subtitle});

  final String? name;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Row(
      children: [
        if (name != null)
          QdAvatarInitial(name: name!, size: 48)
        else
          const QdIconTile(icon: Icons.handshake_outlined, size: 48),
        const SizedBox(width: QdSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title,
                    style: QdText.header
                        .copyWith(fontSize: 20, color: c.textPrimary)),
              ),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: QdText.secondary.copyWith(color: c.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Original (struck through) vs proposed price and the difference chip.
class _PriceComparison extends StatelessWidget {
  const _PriceComparison({required this.original, required this.proposed});

  final double original;
  final double proposed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final diff = ((proposed - original) * 100).round() / 100;
    final (String chip, QdTone tone) = diff > 0
        ? (l10n.ordPriceMore(formatMoney(l10n, diff)), QdTone.warning)
        : diff < 0
            ? (l10n.ordPriceLess(formatMoney(l10n, -diff)), QdTone.success)
            : (l10n.ordPriceSame, QdTone.neutral);
    final caption = QdText.secondary.copyWith(color: c.textSecondary);
    return Container(
      key: const Key('ord_price_compare'),
      padding: const EdgeInsets.all(QdSpace.x5),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.ordOriginalPrice, style: caption),
                      const SizedBox(height: QdSpace.x1),
                      Text(
                        formatMoney(l10n, original),
                        key: const Key('ord_original_price'),
                        style: QdText.header.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          // Strike-through old price: textMuted's one use.
                          color: c.textMuted,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.ordOfferedPrice, style: caption),
                      const SizedBox(height: QdSpace.x1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          formatMoney(l10n, proposed),
                          key: const Key('ord_proposed_price'),
                          style: QdText.screenTitleLg
                              .copyWith(color: c.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x4),
          QdStatusChip(
              key: const Key('ord_price_diff'), label: chip, tone: tone),
        ],
      ),
    );
  }
}

/// Counter-offer input with the allowed range under it.
class _CounterOffer extends StatelessWidget {
  const _CounterOffer({
    required this.controller,
    required this.suggested,
    required this.error,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final double suggested;
  final String? error;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final b = counterOfferBounds(suggested);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.ordOriginalPrice,
                  style: QdText.body.copyWith(color: c.textSecondary)),
            ),
            Text(formatMoney(l10n, suggested),
                style: QdText.bodyStrong.copyWith(color: c.textPrimary)),
          ],
        ),
        const SizedBox(height: QdSpace.x4),
        QdTextField(
          key: const Key('ord_offer_input'),
          label: l10n.ordYourPrice,
          controller: controller,
          ltr: true,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSubmit(),
          hint: suggested == suggested.roundToDouble()
              ? suggested.toStringAsFixed(0)
              : suggested.toStringAsFixed(2),
          helperText: l10n.ordPriceRange(
              formatMoney(l10n, b.min), formatMoney(l10n, b.max)),
          errorText: error,
        ),
      ],
    );
  }
}
