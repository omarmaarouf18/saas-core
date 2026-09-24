class JobLocation {
  final double latitude;
  final double longitude;

  JobLocation({required this.latitude, required this.longitude});

  /// Shared, testable "lat, lon" formatter for per-job route display
  /// (e.g. RouteTimeline detail lines). Fixed 4-decimal precision matches
  /// the coordinate rendering precedent in customer_marketplace_screen.
  String formatCoordinates() =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  factory JobLocation.fromJson(Map<String, dynamic> json) {
    return JobLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };
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
    );
  }
}
