import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../models/marketplace_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/marketplace_provider.dart';
import '../../ui/qd_ui.dart';
import 'booking_rules.dart';
import 'customer_format.dart';
import 'customer_location.dart';
import 'customer_nav.dart';
import 'picker_page.dart';
import 'price_estimate.dart';
import 'service_photo_tile.dart';

/// Booking page (A-Book): the chosen company, pickup and drop-off (each
/// opens the picker, with address text and a landmark note), who receives
/// it ("I am the recipient" by default, or someone else's name, phone and
/// notes), the package size and notes (delivery and shipping only), the
/// client price estimate, and cash on delivery as the only payment. "Order
/// now" stays disabled until a drop-off is set.
///
/// A booking is exactly: service + pickup + destination (+ optional
/// address text and notes) + optional recipient + optional package details
/// (job model v2, sent only when filled in) + payment_method "cod". Field
/// checks mirror the server's; a server 400 code shows on its field. Electronic payment is not offered: the backend
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
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => CustomerBookingPage(service: service, pickup: pickup),
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

  /// "Someone else" receives it; false = "I am the recipient" (default).
  bool _someoneElse = false;
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _recipientNotes = TextEditingController();
  String? _packageSize;
  final _packageNotes = TextEditingController();
  Map<BookingField, BookingError> _fieldErrors = const {};

  bool get _withPackage => packageApplies(widget.service.category);

  @override
  void dispose() {
    _recipientName.dispose();
    _recipientPhone.dispose();
    _recipientNotes.dispose();
    _packageNotes.dispose();
    super.dispose();
  }

  BookingExtras _extras(PickedPlace dropoff) => BookingExtras(
        pickupAddress: _pickup.trimmedAddress,
        pickupNote: _pickup.trimmedNote,
        dropoffAddress: dropoff.trimmedAddress,
        dropoffNote: dropoff.trimmedNote,
        someoneElse: _someoneElse,
        recipientName: _recipientName.text,
        recipientPhone: _recipientPhone.text,
        recipientNotes: _recipientNotes.text,
        packageSize: _packageSize,
        packageNotes: _packageNotes.text,
        withPackage: _withPackage,
      );

  /// Typing in a field clears its error (and the banner once none is left).
  void _clearError(BookingField field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() {
      _fieldErrors = Map.of(_fieldErrors)..remove(field);
      if (_fieldErrors.isEmpty) _error = null;
    });
  }

  String? _errorOf(BookingField field) {
    final e = _fieldErrors[field];
    return e == null ? null : bookingErrorText(context.l10n, field, e);
  }

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
    _clearError(BookingField.route);
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
    final extras = _extras(dropoff);
    final invalid = validateBooking(extras);
    if (invalid.isNotEmpty) {
      setState(() {
        _fieldErrors = invalid;
        _error = l10n.bookFixFields;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final job = await marketplace.bookJobWithDetails(
        serviceId: widget.service.id,
        userId: token ?? '',
        latitude: _pickup.latitude,
        longitude: _pickup.longitude,
        destinationLatitude: dropoff.latitude,
        destinationLongitude: dropoff.longitude,
        paymentMethod: 'cod',
        pickupAddressNote: _pickup.trimmedNote,
        destinationAddressNote: dropoff.trimmedNote,
        pickupAddress: extras.pickupAddress,
        destinationAddress: extras.dropoffAddress,
        recipient: extras.recipient,
        packageDetails: extras.package,
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
      final field = serverBookingError(e);
      setState(() {
        _submitting = false;
        if (field != null) {
          _fieldErrors = {field.key: field.value};
          _error = l10n.bookFixFields;
        } else {
          _error = l10n.custBookingFailed(friendlyErrorMessage(e));
        }
      });
    }
  }

  /// "Who receives it?" ("Who's riding?" for rides): I am / someone else,
  /// then name, phone and notes for someone else.
  List<Widget> _recipientSection(AppLocalizations l10n, TextStyle title) {
    final ride = isRide(widget.service.category);
    return [
      Semantics(
          header: true,
          child: Text(ride ? l10n.bookPassengerTitle : l10n.bookRecipientTitle,
              style: title)),
      const SizedBox(height: QdSpace.x2),
      QdSegmented<bool>(
        key: const Key('cust_book_recipient_toggle'),
        segments: [
          QdSegment(
              value: false,
              label: ride ? l10n.bookPassengerMe : l10n.bookRecipientMe),
          QdSegment(value: true, label: l10n.bookRecipientOther),
        ],
        selected: _someoneElse,
        onChanged: (v) {
          if (_submitting) return;
          setState(() {
            _someoneElse = v;
            // Errors of hidden fields go away with them.
            _fieldErrors = Map.of(_fieldErrors)
              ..remove(BookingField.recipientName)
              ..remove(BookingField.recipientPhone)
              ..remove(BookingField.recipientNotes);
            if (_fieldErrors.isEmpty) _error = null;
          });
        },
      ),
      if (_someoneElse) ...[
        const SizedBox(height: QdSpace.x3),
        QdTextField(
          key: const Key('cust_book_recipient_name'),
          label: l10n.bookRecipientName,
          hint: ride ? l10n.bookPassengerNameHint : l10n.bookRecipientNameHint,
          controller: _recipientName,
          enabled: !_submitting,
          errorText: _errorOf(BookingField.recipientName),
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          inputFormatters: [
            LengthLimitingTextInputFormatter(kRecipientNameMaxLength),
          ],
          onChanged: (_) => _clearError(BookingField.recipientName),
        ),
        const SizedBox(height: QdSpace.x3),
        QdTextField(
          key: const Key('cust_book_recipient_phone'),
          label: l10n.bookRecipientPhone,
          hint: '01012345678',
          helperText: l10n.bookRecipientPhoneHelp,
          controller: _recipientPhone,
          enabled: !_submitting,
          errorText: _errorOf(BookingField.recipientPhone),
          ltr: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            // Spaces and dashes are dropped before sending.
            LengthLimitingTextInputFormatter(kRecipientPhoneMaxLength + 6),
          ],
          onChanged: (_) => _clearError(BookingField.recipientPhone),
        ),
        const SizedBox(height: QdSpace.x3),
        QdTextField(
          key: const Key('cust_book_recipient_notes'),
          label: l10n.bookRecipientNotes,
          hint: l10n.bookRecipientNotesHint,
          controller: _recipientNotes,
          enabled: !_submitting,
          errorText: _errorOf(BookingField.recipientNotes),
          maxLines: 2,
          inputFormatters: [
            LengthLimitingTextInputFormatter(kRecipientNotesMaxLength),
          ],
          onChanged: (_) => _clearError(BookingField.recipientNotes),
        ),
      ],
    ];
  }

  /// Package size (not specified / small / medium / large) and notes.
  List<Widget> _packageSection(
      AppLocalizations l10n, QdColors c, TextStyle title) {
    final sizeError = _errorOf(BookingField.packageSize);
    return [
      Semantics(header: true, child: Text(l10n.bookPackageTitle, style: title)),
      const SizedBox(height: QdSpace.x2),
      Text(l10n.bookPackageSize,
          style: QdText.secondary.copyWith(color: c.textSecondary)),
      const SizedBox(height: QdSpace.x2),
      QdChoiceChips<String?>(
        key: const Key('cust_book_package_size'),
        semanticLabel: l10n.bookPackageSize,
        choices: [
          QdChoice(value: null, label: l10n.bookSizeNone),
          for (final size in kPackageSizes)
            QdChoice(value: size, label: packageSizeLabel(l10n, size)),
        ],
        selected: _packageSize,
        onChanged: (v) {
          if (_submitting) return;
          setState(() => _packageSize = v);
          _clearError(BookingField.packageSize);
        },
      ),
      const SizedBox(height: QdSpace.x1),
      Text(sizeError ?? l10n.bookPackageNoPrice,
          key: sizeError == null ? null : const Key('cust_book_size_error'),
          style: QdText.caption
              .copyWith(color: sizeError == null ? c.textSecondary : c.danger)),
      const SizedBox(height: QdSpace.x3),
      QdTextField(
        key: const Key('cust_book_package_notes'),
        label: l10n.bookPackageNotes,
        hint: l10n.bookPackageNotesHint,
        controller: _packageNotes,
        enabled: !_submitting,
        errorText: _errorOf(BookingField.packageNotes),
        maxLines: 2,
        inputFormatters: [
          LengthLimitingTextInputFormatter(kPackageNotesMaxLength),
        ],
        onChanged: (_) => _clearError(BookingField.packageNotes),
      ),
    ];
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
              ServicePhotoTile(
                  key: const Key('cust_book_service_photo'),
                  serviceId: service.id,
                  photoUrl: service.photoUrl,
                  name: service.name,
                  size: 44),
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
          if (_errorOf(BookingField.route) case final routeError?) ...[
            const SizedBox(height: QdSpace.x2),
            Text(routeError,
                key: const Key('cust_book_route_error'),
                style: QdText.caption.copyWith(color: c.danger)),
          ],
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
          const SizedBox(height: QdSpace.x5),
          ..._recipientSection(l10n, sectionTitle),
          if (_withPackage) ...[
            const SizedBox(height: QdSpace.x5),
            ..._packageSection(l10n, c, sectionTitle),
          ],
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
