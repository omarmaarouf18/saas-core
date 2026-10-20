import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/marketplace_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/marketplace_provider.dart';
import '../../ui/qd_ui.dart';
import 'customer_format.dart';
import 'customer_location.dart';
import 'customer_nav.dart';
import 'customer_theme.dart';
import 'picker_page.dart';
import 'price_estimate.dart';

/// Booking page (A-Book): the chosen company, pickup and drop-off (each
/// opens the picker), the client price estimate, and cash on delivery as
/// the only payment. "Order now" stays disabled until a drop-off is set.
///
/// A booking is exactly: service + pickup + destination (+ optional notes)
/// + payment_method "cod". Electronic payment is not offered: the backend
/// accepts only COD in production (DIGITAL_PAYMENTS off) and no gateway
/// exists, so the row only says it is coming soon.
class CustomerBookingPage extends StatefulWidget {
  const CustomerBookingPage({
    super.key,
    required this.service,
    required this.pickup,
  });

  final MarketplaceService service;
  final PickedPlace pickup;

  static Future<void> open(BuildContext context,
          {required MarketplaceService service, required PickedPlace pickup}) =>
      Navigator.of(context).push<void>(customerRoute(
        (_) => CustomerBookingPage(service: service, pickup: pickup),
      ));

  @override
  State<CustomerBookingPage> createState() => _CustomerBookingPageState();
}

class _CustomerBookingPageState extends State<CustomerBookingPage> {
  late PickedPlace _pickup = widget.pickup;
  PickedPlace? _dropoff;
  bool _submitting = false;
  bool _booked = false;
  String? _error;

  bool get _closed => widget.service.isOpenNow == false;
  bool get _ready => _dropoff != null && !_closed && !_booked;

  Future<void> _pick({required bool pickup}) async {
    final l10n = context.l10n;
    final picked = await CustomerPickerPage.open(
      context,
      title: pickup ? l10n.custPickupPlace : l10n.custDropoffPlace,
      // The drop-off picker starts on the pickup, never auto-locating.
      initial: pickup
          ? _pickup
          : _dropoff ??
              PickedPlace(
                  latitude: _pickup.latitude, longitude: _pickup.longitude),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (pickup) {
        _pickup = picked;
      } else {
        _dropoff = picked;
      }
    });
  }

  Future<void> _submit() async {
    // Double-submit guard: one booking request at a time.
    if (!_ready || _submitting) return;
    final dropoff = _dropoff!;
    final l10n = context.l10n;
    final marketplace = context.read<MarketplaceProvider>();
    final token = context.read<AuthProvider>().token;
    final nav = CustomerNavScope.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final job = await marketplace.bookJob(
        serviceId: widget.service.id,
        userId: token ?? '',
        latitude: _pickup.latitude,
        longitude: _pickup.longitude,
        destinationLatitude: dropoff.latitude,
        destinationLongitude: dropoff.longitude,
        paymentMethod: 'cod',
        pickupAddressNote: _pickup.trimmedNote,
        destinationAddressNote: dropoff.trimmedNote,
      );
      if (!mounted) return;
      if (job == null) {
        setState(() {
          _submitting = false;
          _error = l10n.custBookingFailed(l10n.qdErrorBody);
        });
        return;
      }
      // Refresh "My orders" in the background; the order opens right away.
      unawaited(marketplace.fetchCustomerJobs(token));
      setState(() {
        _submitting = false;
        _booked = true; // never book the same trip twice from this page
      });
      await nav.openOrder(context, job, replaceStack: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = l10n.custBookingFailed(friendlyErrorMessage(e));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final service = widget.service;
    final dropoff = _dropoff;
    final estimate = dropoff == null
        ? null
        : estimateTripPrice(
            service: service,
            fromLat: _pickup.latitude,
            fromLon: _pickup.longitude,
            toLat: dropoff.latitude,
            toLon: dropoff.longitude,
          );
    final sectionTitle = QdText.rowTitleSm.copyWith(color: c.textPrimary);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.custConfirmOrder)),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(
            QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x4),
        children: [
          Row(
            children: [
              QdIconTile.initialOf(service.name, size: 44),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.name,
                        style:
                            QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                    Text(categoryLabel(l10n, service.category),
                        style:
                            QdText.secondary.copyWith(color: c.textSecondary)),
                  ],
                ),
              ),
              QdButton.text(
                key: const Key('cust_book_change_service'),
                label: l10n.custChange,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          if (_closed) ...[
            const SizedBox(height: QdSpace.x4),
            QdBanner(
                tone: QdBannerTone.danger, message: l10n.custServiceClosed),
          ],
          const SizedBox(height: QdSpace.x5),
          Semantics(
              header: true,
              child: Text(l10n.custRouteTitle, style: sectionTitle)),
          const SizedBox(height: QdSpace.x2),
          QdRouteStops(
            key: const Key('cust_book_route'),
            pickup: QdRouteStop(
              caption: l10n.qdPickup,
              value: placeTitle(l10n, _pickup),
              note: placeNote(_pickup),
              placeholder: l10n.custChooseLocation,
              onTap: _submitting ? null : () => _pick(pickup: true),
            ),
            dropoff: QdRouteStop(
              caption: l10n.qdDropoff,
              value: dropoff == null ? null : placeTitle(l10n, dropoff),
              note: dropoff == null ? null : placeNote(dropoff),
              placeholder: l10n.custChooseDropoff,
              onTap: _submitting ? null : () => _pick(pickup: false),
            ),
          ),
          const SizedBox(height: QdSpace.x5),
          Semantics(
              header: true,
              child: Text(l10n.custPriceTitle, style: sectionTitle)),
          const SizedBox(height: QdSpace.x2),
          estimate == null
              ? QdPriceBreakdown(
                  key: const Key('cust_book_price'),
                  lines: [
                    QdPriceLine(
                        label: l10n.custBaseFare,
                        value: formatMoney(l10n, baseFareOf(service))),
                    QdPriceLine(
                        label: l10n.custPerKm,
                        value: formatMoney(l10n, service.tenantPricePerKM)),
                  ],
                  note: l10n.custPriceNeedsDropoff,
                )
              : QdPriceBreakdown(
                  key: const Key('cust_book_price'),
                  lines: [
                    QdPriceLine(
                        label: l10n.custBaseFare,
                        value: formatMoney(l10n, estimate.base)),
                    QdPriceLine(
                      label: l10n.custDistanceLine(
                          formatKm(estimate.distanceKm),
                          formatMoney(l10n, estimate.ratePerKm)),
                      value: formatMoney(l10n, estimate.distanceCost),
                    ),
                  ],
                  totalLabel: l10n.custEstimate,
                  totalValue:
                      l10n.custAboutAmount(formatMoney(l10n, estimate.total)),
                  note: l10n.custPriceDisclaimer,
                ),
          const SizedBox(height: QdSpace.x5),
          QdCard(
            key: const Key('cust_book_payment'),
            subtle: true,
            padding: const EdgeInsets.all(14),
            child: MergeSemantics(
              child: Row(
                children: [
                  Icon(Icons.payments_outlined,
                      size: QdSize.iconLg, color: c.textPrimary),
                  const SizedBox(width: QdSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.custPayCash,
                            style: QdText.rowTitleSm
                                .copyWith(color: c.textPrimary)),
                        Text(l10n.custPayOnlineSoon,
                            style: QdText.caption
                                .copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: QdFooterBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Next to the button, so it is visible without scrolling.
            if (_error != null) ...[
              QdBanner(
                key: const Key('cust_book_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: _error!,
              ),
              const SizedBox(height: QdSpace.x3),
            ],
            QdButton(
              key: const Key('cust_book_submit'),
              label: dropoff == null
                  ? l10n.custChooseDropoffFirst
                  : l10n.custOrderNow,
              fullWidth: true,
              loading: _submitting,
              // Stays enabled while loading so it keeps its gold fill;
              // QdButton ignores taps while [loading].
              onPressed: _ready ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
