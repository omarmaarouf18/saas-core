import 'job.dart';

class ReconciliationJob {
  final String id;
  final String ownerId;
  final String serviceId;
  final String userId;
  final String? employeeId;
  final String status;
  final JobLocation location;
  final JobLocation? currentLocation;
  final String paymentMethod;
  final double lockedEscrowAmount;
  final String reconciliationNote;
  final String escrowFailureReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReconciliationJob({
    required this.id,
    required this.ownerId,
    required this.serviceId,
    required this.userId,
    this.employeeId,
    required this.status,
    required this.location,
    this.currentLocation,
    required this.paymentMethod,
    required this.lockedEscrowAmount,
    required this.reconciliationNote,
    required this.escrowFailureReason,
    this.createdAt,
    this.updatedAt,
  });

  factory ReconciliationJob.fromJson(Map<String, dynamic> json) {
    return ReconciliationJob(
      id: json['id'] ?? '',
      ownerId: json['owner_id'] ?? '',
      serviceId: json['service_id'] ?? '',
      userId: json['user_id'] ?? '',
      employeeId: json['employee_id'],
      status: json['status'] ?? 'escrow_reconciliation_required',
      location: JobLocation.fromJson(json['location'] ?? {}),
      currentLocation: json['current_location'] != null
          ? JobLocation.fromJson(json['current_location'])
          : null,
      paymentMethod: json['payment_method'] ?? '',
      lockedEscrowAmount:
          (json['locked_escrow_amount'] as num?)?.toDouble() ?? 0.0,
      reconciliationNote: json['reconciliation_note'] ?? '',
      escrowFailureReason: json['escrow_failure_reason'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }
}
