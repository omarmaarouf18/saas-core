class EmployeeMarkerData {
  final String employeeId;

  /// Resolved display name looked up from the owner's employee roster.
  /// Null when no matching roster record exists (stale/removed employee or
  /// roster not fetched yet) — renderers must fall back to the raw ID.
  final String? employeeName;
  final String? jobId;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  EmployeeMarkerData({
    required this.employeeId,
    this.employeeName,
    this.jobId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  EmployeeMarkerData copyWith({
    String? employeeId,
    String? employeeName,
    String? jobId,
    double? latitude,
    double? longitude,
    DateTime? updatedAt,
  }) {
    return EmployeeMarkerData(
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      jobId: jobId ?? this.jobId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory EmployeeMarkerData.fromJson(Map<String, dynamic> json) {
    return EmployeeMarkerData(
      employeeId: json['employee_id'] ?? json['sender_id'] ?? 'unknown',
      employeeName: json['employee_name'] as String?,
      jobId: json['job_id'] ??
          json['channel']?.toString().replaceFirst('job:', ''),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
