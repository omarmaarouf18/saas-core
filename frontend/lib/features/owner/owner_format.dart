import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../customer/customer_format.dart';
import 'owner_controller.dart';

export '../customer/customer_format.dart'
    show
        formatKm,
        formatMoney,
        formatWhen,
        jobPlaceLabel,
        jobPrice,
        jobRef,
        jobRefIsolated;

/// Display helpers for the redesigned owner pages (FE-OWNER-1). The
/// order reference, place labels, money and dates come from the customer
/// pages' helpers so both sides show the same `#QD-…`, "Pinned location"
/// and "Today · 2:14 PM".

/// First characters of an id, left-to-right isolated so it keeps its order
/// inside Arabic text. Used where the API gives an id and no name.
String shortIdIsolated(String id) {
  final s = id.length > 6 ? id.substring(0, 6) : id;
  return '\u2066$s\u2069';
}

/// "#" and the first characters of an id in one left-to-right isolate, so
/// the "#" stays in front of the id inside Arabic text ("عميل #cust-9").
String shortRefIsolated(String id) {
  final s = id.length > 6 ? id.substring(0, 6) : id;
  return '\u2066#$s\u2069';
}

/// The courier's username from the employees list; a short id when the
/// courier is not in it (removed, or the list failed to load); null when
/// nobody is assigned.
String? courierNameOf(
    AppLocalizations l10n, OwnerDataController data, String? employeeId) {
  if (employeeId == null || employeeId.isEmpty) return null;
  final e = data.employeeById(employeeId);
  if (e != null && e.displayName.isNotEmpty) return e.displayName;
  return l10n.ownCourierUnknown(shortIdIsolated(employeeId));
}

/// "just now", "12 min ago", "3 h ago", else the date and time.
String formatAgo(BuildContext context, DateTime instant, {DateTime? now}) {
  final l10n = AppLocalizations.of(context)!;
  final diff = (now ?? DateTime.now()).difference(instant);
  if (diff.inMinutes < 1) return l10n.ownAgoNow;
  if (diff.inMinutes < 60) return l10n.ownAgoMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l10n.ownAgoHours(diff.inHours);
  return formatWhen(context, instant, now: now);
}
