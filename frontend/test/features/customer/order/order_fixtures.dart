import 'package:frontend/models/job.dart';

import '../customer_harness.dart';

/// A job with every field the order detail views read.
Job orderJob({
  String id = 'a1b2c3d4e5f6',
  String status = 'pending_dispatch',
  String? employeeId,
  String? offeredEmployeeId,
  String? pickupNote = 'Beside the kiosk',
  String? dropNote = 'Zamalek, 26th of July St',
  String paymentMethod = 'cod',
  double? suggested = 42,
  double? proposed,
  String? proposedBy,
  double? agreed,
  DateTime? proposalExpiresAt,
  String? cancellationReason,
  String? cancellationRequestStatus,
  double? lockedEscrow,
  DateTime? createdAt,
  String serviceId = 'svc-1',
}) =>
    Job(
      id: id,
      ownerId: 'tenant-svc-1',
      employeeId: employeeId,
      userId: 'user-1',
      serviceId: serviceId,
      status: status,
      location: JobLocation(
          latitude: 30.05, longitude: 31.24, addressNote: pickupNote),
      destination:
          JobLocation(latitude: 30.06, longitude: 31.22, addressNote: dropNote),
      paymentMethod: paymentMethod,
      suggestedPrice: suggested,
      proposedPrice: proposed,
      proposedBy: proposedBy,
      agreedPrice: agreed,
      priceProposalExpiresAt: proposalExpiresAt,
      currentOfferedEmployeeId: offeredEmployeeId,
      cancellationReason: cancellationReason,
      cancellationRequestStatus: cancellationRequestStatus,
      lockedEscrowAmount: lockedEscrow,
      createdAt: createdAt ?? fixedNow.subtract(const Duration(minutes: 20)),
    );
