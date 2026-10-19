import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/job.dart';
import '../../models/marketplace_service.dart';
import '../../ui/components/qd_money.dart';
import 'customer_location.dart';

/// Display helpers shared by the redesigned customer pages. Coordinates are
/// never shown: a place without a typed note is "Pinned location" (or "Your
/// current location" when it came from the device).

/// Label for a job's pickup / drop-off: [JobLocation.addressSummary], except
/// that its coordinate fallback becomes the localized "Pinned location".
String jobPlaceLabel(AppLocalizations l10n, JobLocation? location) {
  if (location == null) return l10n.custPinnedLocation;
  final summary = location.addressSummary();
  return summary == location.formatCoordinates()
      ? l10n.custPinnedLocation
      : summary;
}

/// Main line for a picked place: "Your current location" for the device
/// location, otherwise its note, otherwise "Pinned location".
String placeTitle(AppLocalizations l10n, PickedPlace place) {
  if (place.isDeviceLocation) return l10n.custCurrentLocation;
  return place.trimmedNote ?? l10n.custPinnedLocation;
}

/// Second line for a picked place: the note, when the main line is not it.
String? placeNote(PickedPlace place) =>
    place.isDeviceLocation ? place.trimmedNote : null;

String categoryLabel(AppLocalizations l10n, String? category) =>
    switch (category?.trim().toLowerCase()) {
      'delivery' => l10n.custCatDelivery,
      'transport' => l10n.custCatRide,
      'shipping' => l10n.custCatShipping,
      null || '' => l10n.custOrderFallback,
      final other => other,
    };

IconData categoryIcon(String? category) =>
    switch (category?.trim().toLowerCase()) {
      'delivery' => Icons.inventory_2_outlined,
      'transport' => Icons.directions_car_outlined,
      'shipping' => Icons.local_shipping_outlined,
      _ => Icons.receipt_long_outlined,
    };

/// The marketplace service a job was booked on, when it is already loaded
/// (jobs carry only `service_id`; no extra request is made).
MarketplaceService? serviceOfJob(
        Job job, Iterable<MarketplaceService> services) =>
    services.where((s) => s.id == job.serviceId).firstOrNull;

/// Card title for a job: its category when the service is known, else
/// "Order".
String jobTitle(
    AppLocalizations l10n, Job job, Iterable<MarketplaceService> services) {
  final svc = serviceOfJob(job, services);
  return svc == null
      ? l10n.custOrderFallback
      : categoryLabel(l10n, svc.category);
}

/// Short order reference shown to people: `#QD-` + first 8 id characters.
String jobRef(Job job) {
  final id = job.id.length > 8 ? job.id.substring(0, 8) : job.id;
  return '#QD-${id.toUpperCase()}';
}

/// [jobRef] wrapped in a left-to-right isolate, so "#QD-…" keeps its order
/// inside Arabic text.
String jobRefIsolated(Job job) => '\u2066${jobRef(job)}\u2069';

/// The price to show for a job: agreed price, else the server's suggested
/// price; null when neither is known yet.
double? jobPrice(Job job) => job.agreedPrice ?? job.suggestedPrice;

final NumberFormat _km = NumberFormat('#,##0.#', 'en');

/// Distance with at most one decimal, Western digits ("2.4", "12").
String formatKm(double km) => _km.format(km);

String formatMoney(AppLocalizations l10n, num amount) =>
    QdMoney.format(l10n, amount);

/// "Today · 2:14 PM" or "Oct 18 · 2:14 PM", in the device time zone.
String formatWhen(BuildContext context, DateTime instant, {DateTime? now}) {
  final l10n = AppLocalizations.of(context)!;
  final ml = MaterialLocalizations.of(context);
  final local = instant.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time = ml.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  final sameDay = local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay
      ? l10n.custTodayAt(time)
      : l10n.custDateAt(ml.formatShortMonthDay(local), time);
}

/// Step shown on the ongoing-order progress bar (4 segments: looking for a
/// courier, courier assigned, on the way, done).
int jobProgressStep(String? status) => switch (status?.trim().toLowerCase()) {
      'assigned' => 1,
      'active' => 2,
      'completed' ||
      'escrow_reconciliation_required' ||
      'reconciliation_required' =>
        3,
      _ => 0,
    };

const int kJobProgressSteps = 4;

/// Widest a row's trailing status chips may get before they wrap / ellipsize.
const double kChipsMaxWidth = 150;
