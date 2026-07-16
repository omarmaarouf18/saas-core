class JobLocation {
  final double latitude;
  final double longitude;

  JobLocation({required this.latitude, required this.longitude});

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
  final JobLocation? currentLocation;
  final String paymentMethod;
  final String? cancellationReason;
  final double? lockedEscrowAmount;
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
    this.currentLocation,
    required this.paymentMethod,
    this.cancellationReason,
    this.lockedEscrowAmount,
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
      currentLocation: json['current_location'] != null
          ? JobLocation.fromJson(json['current_location'])
          : null,
      paymentMethod: json['payment_method'] ?? '',
      cancellationReason: json['cancellation_reason'],
      lockedEscrowAmount: (json['locked_escrow_amount'] as num?)?.toDouble(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }
}
