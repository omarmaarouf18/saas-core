class JobLocation {
  final double latitude;
  final double longitude;

  /// Option C: optional customer/owner-typed landmark note (e.g. "beside
  /// Ahmed's kiosk") helping the courier find the pin. Free text, never
  /// validated as an address (backend caps length at creation). Null or
  /// empty means no note was provided — callers fall back to the map
  /// preview (Option A), never to raw coordinates as the primary signal.
  final String? addressNote;

  /// Job model v2 (ADR-0028 §2.2): street / area text typed or picked by
  /// the customer at booking. Null on legacy jobs and when none was given.
  final String? address;

  JobLocation(
      {required this.latitude,
      required this.longitude,
      this.addressNote,
      this.address});

  /// Shared, testable "lat, lon" formatter for per-job route display
  /// (e.g. RouteTimeline detail lines). Fixed 4-decimal precision matches
  /// the coordinate rendering precedent in customer_marketplace_screen.
  String formatCoordinates() =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  /// Compact address summary (Option C display rule, shared): the typed
  /// landmark note when one was entered, coordinates only when nothing
  /// was. Matches the booking-dialog presentation (note-primary,
  /// coords-fallback) so map sheets and booking flows never disagree.
  String addressSummary() {
    final note = addressNote?.trim() ?? '';
    if (note.isNotEmpty) return note;
    return formatCoordinates();
  }

  factory JobLocation.fromJson(Map<String, dynamic> json) {
    return JobLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      addressNote: (json['address_note'] as String?)?.trim().isNotEmpty == true
          ? (json['address_note'] as String).trim()
          : null,
      address: _optionalText(json['address']),
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        if (addressNote != null && addressNote!.isNotEmpty)
          'address_note': addressNote,
        if (address != null && address!.isNotEmpty) 'address': address,
      };
}

/// Trimmed string, or null when [value] is not a non-blank string.
String? _optionalText(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _optionalNum(Object? value) => value is num ? value.toDouble() : null;

DateTime? _optionalTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Job model v2 (ADR-0028 §2.1): who receives the package. The courier
/// sees the phone only while the job is active (the server redacts it
/// afterwards).
class JobRecipient {
  final String? name;
  final String? phone;
  final String? notes;

  const JobRecipient({this.name, this.phone, this.notes});

  bool get isEmpty => name == null && phone == null && notes == null;

  /// Null when [json] is not an object or carries none of the fields.
  static JobRecipient? fromJson(Object? json) {
    if (json is! Map) return null;
    final r = JobRecipient(
      name: _optionalText(json['name']),
      phone: _optionalText(json['phone']),
      notes: _optionalText(json['notes']),
    );
    return r.isEmpty ? null : r;
  }
}

/// Job model v2 (ADR-0028 §2.7): package size ("small" | "medium" |
/// "large", unset by default) and notes. Informational only.
class JobPackageDetails {
  final String? size;
  final String? notes;

  const JobPackageDetails({this.size, this.notes});

  /// Null when [json] is not an object or carries none of the fields.
  static JobPackageDetails? fromJson(Object? json) {
    if (json is! Map) return null;
    final size = _optionalText(json['size'])?.toLowerCase();
    final notes = _optionalText(json['notes']);
    if (size == null && notes == null) return null;
    return JobPackageDetails(size: size, notes: notes);
  }
}

/// Job model v2 (ADR-0028 §2.3): one server-written timeline entry.
class JobStatusHistoryEntry {
  final String status;
  final String? subStatus;
  final DateTime at;
  final String? actorRole;
  final String? actorId;
  final String? reason;

  const JobStatusHistoryEntry({
    required this.status,
    required this.at,
    this.subStatus,
    this.actorRole,
    this.actorId,
    this.reason,
  });

  /// Null when [json] is not an object, has no status or no valid time.
  static JobStatusHistoryEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final status = _optionalText(json['status']);
    final at = _optionalTime(json['at']);
    if (status == null || at == null) return null;
    return JobStatusHistoryEntry(
      status: status,
      at: at,
      subStatus: _optionalText(json['sub_status']),
      actorRole: _optionalText(json['actor_role']),
      actorId: _optionalText(json['actor_id']),
      reason: _optionalText(json['reason']),
    );
  }

  /// Valid entries of a `status_history` array; empty for anything else.
  static List<JobStatusHistoryEntry> listFromJson(Object? json) {
    if (json is! List) return const [];
    return [
      for (final e in json)
        if (JobStatusHistoryEntry.fromJson(e) case final entry?) entry,
    ];
  }
}

/// FIX-COD-RECON: a COD job completed with a tracked distance under the
/// ADR-0007 threshold; the owner reviews it.
class JobDistanceReview {
  final double actualKm;
  final double bookedKm;
  final DateTime? flaggedAt;
  final String? source;

  const JobDistanceReview({
    required this.actualKm,
    required this.bookedKm,
    this.flaggedAt,
    this.source,
  });

  static JobDistanceReview? fromJson(Object? json) {
    if (json is! Map) return null;
    return JobDistanceReview(
      actualKm: _optionalNum(json['actual_km']) ?? 0,
      bookedKm: _optionalNum(json['booked_km']) ?? 0,
      flaggedAt: _optionalTime(json['flagged_at']),
      source: _optionalText(json['source']),
    );
  }
}

class Job {
  final String id;
  final String ownerId;
  final String? employeeId;
  final String userId;
  final String serviceId;
  final String status; // pending, active, completed, cancelled
  final JobLocation location;
  final JobLocation? destination;
  final JobLocation? currentLocation;
  final String paymentMethod;
  final String? cancellationReason;
  final double? lockedEscrowAmount;
  final double? suggestedPrice;
  final double? proposedPrice;
  final String? proposedBy;
  final double? agreedPrice;
  final DateTime? priceProposalExpiresAt;
  final String? currentOfferedEmployeeId;
  final DateTime? offerExpiresAt;
  final List<String>? offeredEmployeeIds;
  final String? cancellationRequestReason;
  final DateTime? cancellationRequestedAt;
  final String? cancellationRequestStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // --- Job model v2 (ADR-0028), all optional; legacy jobs omit them. ---

  /// `heading_to_pickup` | `picked_up`, only while `status == active`.
  final String? subStatus;

  /// Server-written timeline; empty on legacy jobs (never synthesized).
  final List<JobStatusHistoryEntry> statusHistory;

  /// Straight-line ETA snapshot taken at acceptance and at pickup.
  final int? estimatedDurationMinutes;
  final JobRecipient? recipient;
  final JobPackageDetails? packageDetails;

  /// Customer view only, while the job is active (ADR-0028 §2.6).
  final String? courierPhone;
  final JobDistanceReview? distanceReview;

  Job({
    required this.id,
    required this.ownerId,
    this.employeeId,
    required this.userId,
    required this.serviceId,
    required this.status,
    required this.location,
    this.destination,
    this.currentLocation,
    required this.paymentMethod,
    this.cancellationReason,
    this.lockedEscrowAmount,
    this.suggestedPrice,
    this.proposedPrice,
    this.proposedBy,
    this.agreedPrice,
    this.priceProposalExpiresAt,
    this.currentOfferedEmployeeId,
    this.offerExpiresAt,
    this.offeredEmployeeIds,
    this.cancellationRequestReason,
    this.cancellationRequestedAt,
    this.cancellationRequestStatus,
    this.createdAt,
    this.updatedAt,
    this.subStatus,
    this.statusHistory = const [],
    this.estimatedDurationMinutes,
    this.recipient,
    this.packageDetails,
    this.courierPhone,
    this.distanceReview,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'] ?? '',
      ownerId: json['owner_id'] ?? '',
      employeeId: json['employee_id'],
      userId: json['user_id'] ?? '',
      serviceId: json['service_id'] ?? '',
      status: json['status'] ?? 'pending',
      location: JobLocation.fromJson(json['location'] ?? {}),
      destination: json['destination'] != null
          ? JobLocation.fromJson(json['destination'])
          : null,
      currentLocation: json['current_location'] != null
          ? JobLocation.fromJson(json['current_location'])
          : null,
      paymentMethod: json['payment_method'] ?? '',
      cancellationReason: json['cancellation_reason'],
      lockedEscrowAmount: (json['locked_escrow_amount'] as num?)?.toDouble(),
      suggestedPrice: (json['suggested_price'] as num?)?.toDouble(),
      proposedPrice: (json['proposed_price'] as num?)?.toDouble(),
      proposedBy: json['proposed_by'],
      agreedPrice: (json['agreed_price'] as num?)?.toDouble(),
      priceProposalExpiresAt: json['price_proposal_expires_at'] != null
          ? DateTime.tryParse(json['price_proposal_expires_at'])
          : null,
      currentOfferedEmployeeId: json['current_offered_employee_id'],
      offerExpiresAt: json['offer_expires_at'] != null
          ? DateTime.tryParse(json['offer_expires_at'])
          : null,
      offeredEmployeeIds: json['offered_employee_ids'] != null
          ? List<String>.from(json['offered_employee_ids'])
          : null,
      cancellationRequestReason: json['cancellation_request_reason'],
      cancellationRequestedAt: json['cancellation_requested_at'] != null
          ? DateTime.tryParse(json['cancellation_requested_at'])
          : null,
      cancellationRequestStatus: json['cancellation_request_status'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      subStatus: _optionalText(json['sub_status']),
      statusHistory: JobStatusHistoryEntry.listFromJson(json['status_history']),
      estimatedDurationMinutes: switch (json['estimated_duration_minutes']) {
        final num minutes => minutes.toInt(),
        _ => null,
      },
      recipient: JobRecipient.fromJson(json['recipient']),
      packageDetails: JobPackageDetails.fromJson(json['package_details']),
      courierPhone: _optionalText(json['courier_phone']),
      distanceReview: JobDistanceReview.fromJson(json['distance_review']),
    );
  }

  /// Time of the first [statusHistory] entry with [status] (and
  /// [subStatus] when given); null when the history has none.
  DateTime? historyTimeOf(String status, {String? subStatus}) {
    for (final e in statusHistory) {
      if (e.status == status &&
          (subStatus == null || e.subStatus == subStatus)) {
        return e.at;
      }
    }
    return null;
  }
}
