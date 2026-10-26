import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../providers/owner_provider.dart';

/// Rules for the redesigned service setup page (FE-OWNER-2, O-Service).
/// Field rules follow the old OwnerConfigurationScreen and the user-service
/// handlers (`CreateService`, `UpdateService`, `ValidateServiceSchedule`).

/// Backend categories, in the order the page shows them.
const List<String> kServiceCategories = ['delivery', 'transport', 'shipping'];

/// Weekday keys of a per-day schedule (ADR-0025), Monday first like the
/// old editor; the backend accepts any order but needs all seven.
const List<String> kWeekdays = [
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun'
];

/// The distance the live price example uses (O-Service: "a 5 km trip").
const int kPriceExampleKm = 5;

const TimeOfDay kDefaultOpen = TimeOfDay(hour: 9, minute: 0);
const TimeOfDay kDefaultClose = TimeOfDay(hour: 17, minute: 0);

String toHHmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay? parseHHmm(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return TimeOfDay(hour: h, minute: mi);
}

/// Parses an amount or distance typed with Western or Arabic-Indic digits
/// (`١٢٫٥` → 12.5). Null when it is not a number.
double? parseAmount(String raw) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in raw.trim().split('')) {
    final i = eastern.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '٫' || ch == ',') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  final s = b.toString();
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Shows a number from the API in a text field: no ".0" on whole values.
String amountText(Object? v) {
  if (v is! num) return '';
  return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
}

enum ScheduleMode { sameDaily, perDay }

class DayHours {
  DayHours({required this.day, this.open, this.close, this.off = false});

  final String day;
  TimeOfDay? open;
  TimeOfDay? close;
  bool off;
}

/// The weekly hours editor (ADR-0025). [touched] records the owner's
/// intent: loading a stored schedule never sets it, so an untouched editor
/// sends none of the schedule fields (an unknown schedule stays unknown); a
/// touched editor with no [mode] sends `schedule_mode: ""` (explicit clear).
class ServiceHours {
  ServiceHours();

  ScheduleMode? mode;
  TimeOfDay? open;
  TimeOfDay? close;
  List<DayHours> days = [];
  bool touched = false;

  /// From a `GET /users/services` entry. Malformed stored data leaves the
  /// editor empty and untouched, like the old screen.
  factory ServiceHours.fromService(Map<String, dynamic> svc) {
    final h = ServiceHours();
    final mode = svc['schedule_mode']?.toString();
    if (mode == 'same_daily') {
      final o = parseHHmm(svc['open_time']?.toString());
      final c = parseHHmm(svc['close_time']?.toString());
      if (o != null && c != null) {
        h
          ..mode = ScheduleMode.sameDaily
          ..open = o
          ..close = c;
      }
    } else if (mode == 'per_day') {
      final raw = svc['per_day_schedule'];
      if (raw is List && raw.length == 7) {
        final rows = <DayHours>[];
        final seen = <String>{};
        for (final e in raw) {
          if (e is! Map) return h;
          final day = e['day']?.toString().toLowerCase() ?? '';
          if (!kWeekdays.contains(day) || !seen.add(day)) return h;
          rows.add(DayHours(
            day: day,
            open: parseHHmm(e['open_time']?.toString()),
            close: parseHHmm(e['close_time']?.toString()),
            off: e['is_off'] == true,
          ));
        }
        h
          ..mode = ScheduleMode.perDay
          ..days = rows;
      }
    }
    return h;
  }

  /// Turns hours on (same every day, 9:00–17:00 unless already set).
  void start() {
    touched = true;
    mode = ScheduleMode.sameDaily;
    open ??= kDefaultOpen;
    close ??= kDefaultClose;
  }

  void setMode(ScheduleMode m) {
    touched = true;
    mode = m;
    if (m == ScheduleMode.sameDaily) {
      open ??= kDefaultOpen;
      close ??= kDefaultClose;
    } else if (days.isEmpty) {
      days = [
        for (final d in kWeekdays)
          DayHours(
              day: d,
              open: open ?? kDefaultOpen,
              close: close ?? kDefaultClose),
      ];
    }
  }

  /// Removes the hours. Stays touched, so saving sends the explicit clear.
  void clear() {
    touched = true;
    mode = null;
  }
}

enum HoursProblem { missingTime, sameTime }

/// What `ValidateServiceSchedule` would refuse: both times needed and not
/// equal (overnight hours such as 18:00–02:00 are allowed). Keyed by `same`
/// for the daily times, else by weekday.
Map<String, HoursProblem> hoursProblems(ServiceHours h) {
  final out = <String, HoursProblem>{};
  HoursProblem? check(TimeOfDay? o, TimeOfDay? c) {
    if (o == null || c == null) return HoursProblem.missingTime;
    if (o == c) return HoursProblem.sameTime;
    return null;
  }

  switch (h.mode) {
    case null:
      break;
    case ScheduleMode.sameDaily:
      final p = check(h.open, h.close);
      if (p != null) out['same'] = p;
    case ScheduleMode.perDay:
      for (final d in h.days) {
        if (d.off) continue;
        final p = check(d.open, d.close);
        if (p != null) out[d.day] = p;
      }
  }
  return out;
}

/// The schedule part of the PUT body, or null when nothing is to be sent.
class ScheduleFields {
  const ScheduleFields(
      {required this.mode, this.openTime, this.closeTime, this.perDay});

  final String mode;
  final String? openTime;
  final String? closeTime;
  final List<Map<String, dynamic>>? perDay;
}

ScheduleFields? scheduleFieldsOf(ServiceHours h) {
  if (!h.touched) return null;
  switch (h.mode) {
    case null:
      return const ScheduleFields(mode: '');
    case ScheduleMode.sameDaily:
      return ScheduleFields(
        mode: 'same_daily',
        openTime: h.open == null ? null : toHHmm(h.open!),
        closeTime: h.close == null ? null : toHHmm(h.close!),
      );
    case ScheduleMode.perDay:
      return ScheduleFields(mode: 'per_day', perDay: [
        for (final d in h.days)
          {
            'day': d.day,
            'open_time': d.open == null ? '' : toHHmm(d.open!),
            'close_time': d.close == null ? '' : toHHmm(d.close!),
            'is_off': d.off,
          },
      ]);
  }
}

/// Field problems of the form, all at once so every field shows its own.
class ServiceFormProblems {
  const ServiceFormProblems({
    this.name = false,
    this.place = false,
    this.address = false,
    this.radius = false,
    this.baseFee = false,
    this.perKm = false,
    this.hours = const {},
  });

  final bool name;
  final bool place;
  final bool address;
  final bool radius;
  final bool baseFee;
  final bool perKm;
  final Map<String, HoursProblem> hours;

  bool get any =>
      name ||
      place ||
      address ||
      radius ||
      baseFee ||
      perKm ||
      hours.isNotEmpty;
}

/// The old screen's rules: name required; a location; the address empty or
/// at least 3 characters; radius above 0; both prices 0 or more; and the
/// schedule as the server checks it.
ServiceFormProblems validateServiceForm({
  required String name,
  required bool hasPlace,
  required String address,
  required String radius,
  required String baseFee,
  required String perKm,
  required ServiceHours hours,
}) {
  final r = parseAmount(radius);
  final b = parseAmount(baseFee);
  final k = parseAmount(perKm);
  final a = address.trim();
  return ServiceFormProblems(
    name: name.trim().isEmpty,
    place: !hasPlace,
    address: a.isNotEmpty && a.length < 3,
    radius: r == null || r <= 0,
    baseFee: b == null || b < 0,
    perKm: k == null || k < 0,
    hours: hoursProblems(hours),
  );
}

/// The live example: the price a customer sees for [km] km, by the
/// server's formula `tenant_base_price + km × tenant_price_per_km`. Null
/// until both prices are valid.
double? examplePrice(String baseFee, String perKm, {int km = kPriceExampleKm}) {
  final b = parseAmount(baseFee);
  final k = parseAmount(perKm);
  if (b == null || k == null || b < 0 || k < 0) return null;
  return b + km * k;
}

/// The owner's service in a `GET /users/services` listing, as the old
/// screen matched it (`tenant_id`, or `owner_id`).
Map<String, dynamic>? ownServiceOf(
    Iterable<dynamic> services, String? ownerId) {
  if (ownerId == null || ownerId.isEmpty) return null;
  for (final s in services) {
    if (s is Map && (s['tenant_id'] == ownerId || s['owner_id'] == ownerId)) {
      return Map<String, dynamic>.from(s);
    }
  }
  return null;
}

String? serviceIdOf(Map<String, dynamic>? svc) {
  final id = svc?['id']?.toString() ?? svc?['service_id']?.toString() ?? '';
  return id.isEmpty ? null : id;
}

/// Everything the page saves.
class ServiceDraft {
  const ServiceDraft({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.radiusKm,
    required this.baseFee,
    required this.perKm,
    this.schedule,
    this.photoUrl,
  });

  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String address;
  final double radiusKm;
  final double baseFee;
  final double perKm;
  final ScheduleFields? schedule;

  /// A stored photo key to save (uploaded before the service existed);
  /// null leaves the stored photo as it is.
  final String? photoUrl;
}

/// The create worked but the follow-up PUT did not: the service exists
/// with only the fields the POST carried. [serviceId] is null when the
/// create response had no id.
class ServiceSaveIncomplete implements Exception {
  const ServiceSaveIncomplete(this.serviceId, this.cause);

  final String? serviceId;
  final Object? cause;
}

/// Saves [d] and returns the service id.
///
/// An existing service gets one PUT with every field. A new one is created
/// with `POST /users/services` and then gets the same PUT:
/// `OwnerProvider.createService` sends only the name, category, prices and
/// location, so the address, coverage radius and hours would otherwise be
/// dropped on the first save (O-Service note; the provider and backend fix
/// is a follow-up). The free-text working hours are never sent; the photo
/// only as the key an upload returned ([ServiceDraft.photoUrl]).
Future<String> saveService(
  OwnerProvider owner, {
  required String ownerId,
  required String? serviceId,
  required ServiceDraft d,
}) async {
  Future<void> put(String id) => owner.updateOwnerServiceConfig(
        serviceId: id,
        ownerId: ownerId,
        name: d.name,
        category: d.category,
        tenantBasePrice: d.baseFee,
        tenantPricePerKM: d.perKm,
        address: d.address,
        coverageRadiusKm: d.radiusKm,
        latitude: d.latitude,
        longitude: d.longitude,
        scheduleMode: d.schedule?.mode,
        openTime: d.schedule?.openTime,
        closeTime: d.schedule?.closeTime,
        perDaySchedule: d.schedule?.perDay,
        photoUrl: d.photoUrl,
      );

  if (serviceId != null) {
    await put(serviceId);
    return serviceId;
  }
  final res = await owner.createService(
    name: d.name,
    category: d.category,
    tenantBasePrice: d.baseFee,
    tenantPricePerKM: d.perKm,
    latitude: d.latitude,
    longitude: d.longitude,
    ownerId: ownerId,
  );
  final created = res['service'];
  final id =
      serviceIdOf(created is Map ? Map<String, dynamic>.from(created) : null);
  if (id == null) throw const ServiceSaveIncomplete(null, null);
  try {
    await put(id);
  } catch (e) {
    throw ServiceSaveIncomplete(id, e);
  }
  return id;
}

enum ServiceSaveFailure { kybNotApproved, paidPlanRequired, unavailable, other }

/// Create / update refusals from the user-service handlers: 403 "...KYC
/// approval is pending", 402 `upgrade_required`, 503 auth unavailable.
ServiceSaveFailure serviceSaveFailureOf(Object error) {
  if (error is! ApiClientException) return ServiceSaveFailure.other;
  final msg = error.message.toLowerCase();
  if (error.statusCode == 403 && msg.contains('kyc')) {
    return ServiceSaveFailure.kybNotApproved;
  }
  if (error.statusCode == 402 || msg == 'upgrade_required') {
    return ServiceSaveFailure.paidPlanRequired;
  }
  if (error.statusCode == 503) return ServiceSaveFailure.unavailable;
  return ServiceSaveFailure.other;
}
