import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import 'courier_controller.dart';
import 'courier_format.dart';
import 'courier_map.dart';
import 'courier_nav.dart';
import 'courier_route.dart';
import 'courier_rules.dart';
import 'courier_widgets.dart';

/// A dispatch offer (C-Offer), full screen in the Task tab: countdown ring
/// from `offer_expires_at`, mini map, pickup (with the distance from the
/// courier when the position is known) and drop-off (with the trip
/// distance), package details when given, the price (cash to collect for
/// cash orders), chat with the customer, decline / accept.
///
/// Behaviour kept from the old offer card: both buttons and the chat are
/// disabled once the window is over (an offer without an expiry counts as
/// over), a double tap is ignored while an answer is in flight, and the
/// list is refetched after every answer, success or failure. New: when the
/// countdown ends the list is refetched too, and a 409 / 404 / 410 answer
/// says the offer is gone (someone else took it or it moved on).
class CourierOfferPage extends StatefulWidget {
  const CourierOfferPage({super.key, required this.job});

  final Job job;

  @override
  State<CourierOfferPage> createState() => _CourierOfferPageState();
}

class _CourierOfferPageState extends State<CourierOfferPage> {
  bool _busy = false;

  Future<void> _answer({required bool accept}) async {
    if (_busy) return;
    final ctl = context.read<CourierController>();
    if (isOfferExpired(widget.job, ctl.now())) return;
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      if (accept) {
        await ctl.accept(widget.job);
        if (mounted) showCourierNotice(context, l10n.courOfferAccepted);
      } else {
        await ctl.decline(widget.job);
        if (mounted) showCourierNotice(context, l10n.courOfferDeclined);
      }
    } catch (e) {
      if (!mounted) return;
      final status = e is ApiClientException ? e.statusCode : null;
      showCourierNotice(
        context,
        status == 409 || status == 404 || status == 410
            ? l10n.courOfferGone
            : friendlyErrorMessage(e),
        key: const Key('courier_offer_error'),
      );
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
    final expired = isOfferExpired(job, ctl.now());
    final pos = ctl.location.lastKnownPosition;
    final fromYou = pos == null
        ? null
        : kmBetween(pos.latitude, pos.longitude, job.location);
    final trip = tripKm(job);
    final price = priceOf(job);
    final cod = isCod(job);
    final nav = CourierNavScope.of(context);

    return Scaffold(
      key: const Key('courier_offer'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  QdSpace.gutter, 28, QdSpace.gutter, QdSpace.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.courOfferSubtitle,
                            style: QdText.secondary
                                .copyWith(color: c.textSecondary)),
                        Text(l10n.courOfferTitle,
                            style: QdText.screenTitle
                                .copyWith(color: c.textPrimary)),
                      ],
                    ),
                  ),
                  if (job.offerExpiresAt != null)
                    QdCountdown(
                      key: const Key('courier_offer_countdown'),
                      expiresAt: job.offerExpiresAt!,
                      total: kOfferWindow,
                      now: ctl.now,
                      onExpired: _expired,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    QdSpace.gutter, QdSpace.x3, QdSpace.gutter, QdSpace.x4),
                children: [
                  if (expired) ...[
                    QdBanner(
                      key: const Key('courier_offer_expired'),
                      tone: QdBannerTone.warning,
                      icon: Icons.timer_off_outlined,
                      message: l10n.courOfferExpired,
                      actionLabel: l10n.courRefresh,
                      onAction: ctl.reload,
                    ),
                    const SizedBox(height: QdSpace.x4),
                  ],
                  CourierMap(
                    key: const Key('courier_offer_map'),
                    job: job,
                    height: 180,
                    borderRadius: QdRadius.card,
                    self: pos == null
                        ? null
                        : LatLng(pos.latitude, pos.longitude),
                  ),
                  const SizedBox(height: QdSpace.x4),
                  CourierStops(
                    job: job,
                    pickupCaption: fromYou == null
                        ? l10n.qdPickup
                        : l10n.courPickupFromYou(kmLabel(l10n, fromYou)),
                    dropoffCaption: trip == null
                        ? l10n.qdDropoff
                        : l10n.courDropoffTrip(kmLabel(l10n, trip)),
                  ),
                  if (job.packageDetails != null) ...[
                    const SizedBox(height: QdSpace.x4),
                    CourierPackageLine(job: job),
                  ],
                  const SizedBox(height: QdSpace.x4),
                  Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        QdSpace.x4, 14, QdSpace.x2, 14),
                    decoration: BoxDecoration(
                      color: c.fillSubtle,
                      border: Border.all(color: c.border),
                      borderRadius: BorderRadius.circular(QdRadius.card),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  cod
                                      ? l10n.courCashToCollect
                                      : l10n.courOrderPrice,
                                  style: QdText.secondary
                                      .copyWith(color: c.textSecondary)),
                              Text(
                                price == null
                                    ? l10n.courPriceNotSet
                                    : formatMoney(l10n, price),
                                key: const Key('courier_offer_price'),
                                style: QdText.amountLg
                                    .copyWith(color: c.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        QdButton.text(
                          key: const Key('courier_offer_chat'),
                          label: l10n.courAskCustomer,
                          icon: Icons.chat_bubble_outline,
                          small: true,
                          onPressed:
                              expired ? null : () => nav.openChat(context, job),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  QdSpace.gutter, QdSpace.x3, QdSpace.gutter, QdSpace.x4),
              child: Row(
                children: [
                  Expanded(
                    child: QdButton.secondary(
                      key: const Key('courier_offer_decline'),
                      label: l10n.courDecline,
                      fullWidth: true,
                      onPressed: _busy || expired
                          ? null
                          : () => _answer(accept: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: QdButton(
                      key: const Key('courier_offer_accept'),
                      label: l10n.courAccept,
                      fullWidth: true,
                      loading: _busy,
                      onPressed: expired ? null : () => _answer(accept: true),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
