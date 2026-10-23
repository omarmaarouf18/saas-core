import 'dart:math' as math;

import '../../l10n/app_localizations.dart';
import '../../models/job.dart';
import '../customer/customer_format.dart' show formatKm, formatMoney;

export '../customer/customer_format.dart'
    show formatKm, formatMoney, jobRef, jobRefIsolated;

/// Display helpers of the redesigned courier pages (FE-COURIER).
/// Coordinates are never shown.

/// A place as two lines: the address text (v2) when there is one, else the
/// landmark note, else "Pinned location"; [note] is the landmark note when
/// it is not already the title.
({String title, String? note}) placeOf(
    AppLocalizations l10n, JobLocation? location) {
  final address = location?.address;
  final note = location?.addressNote?.trim();
  final hasNote = note != null && note.isNotEmpty;
  if (address != null && address.isNotEmpty) {
    return (title: address, note: hasNote ? note : null);
  }
  if (hasNote) return (title: note, note: null);
  return (title: l10n.custPinnedLocation, note: null);
}

/// Great-circle distance in km.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Straight-line pickup → drop-off distance; null without a destination.
double? tripKm(Job job) {
  final d = job.destination;
  if (d == null) return null;
  return haversineKm(
      job.location.latitude, job.location.longitude, d.latitude, d.longitude);
}

/// Straight-line distance from the courier ([lat], [lng]) to [to].
double kmBetween(double lat, double lng, JobLocation to) =>
    haversineKm(lat, lng, to.latitude, to.longitude);

/// "2.4 km" (localized unit).
String kmLabel(AppLocalizations l10n, double km) => l10n.courKm(formatKm(km));

bool isCod(Job job) => job.paymentMethod.trim().toLowerCase() == 'cod';

/// The order price: agreed, else the server's suggested price.
double? priceOf(Job job) => job.agreedPrice ?? job.suggestedPrice;

/// Money line for a job's price, or "not set yet".
String priceLabel(AppLocalizations l10n, Job job) {
  final p = priceOf(job);
  return p == null ? l10n.courPriceNotSet : formatMoney(l10n, p);
}

String? packageSizeLabel(AppLocalizations l10n, String? size) => switch (size) {
      'small' => l10n.courPackageSmall,
      'medium' => l10n.courPackageMedium,
      'large' => l10n.courPackageLarge,
      null || '' => null,
      final other => other,
    };
