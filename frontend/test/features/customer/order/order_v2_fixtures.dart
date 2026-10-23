import 'package:frontend/models/job.dart';

import '../customer_harness.dart';

/// Job model v2 order (FE-V2-CONSUME): history relative to [fixedNow],
/// address text, recipient, package, ETA and courier phone as given.
Job orderJobV2({
  String status = 'active',
  String? subStatus = 'picked_up',
  int? etaMinutes = 12,
  String? courierPhone = '+201098765432',
  JobRecipient? recipient = const JobRecipient(
      name: 'Mahmoud', phone: '+201012345678', notes: 'Call before arriving'),
  JobPackageDetails? package =
      const JobPackageDetails(size: 'small', notes: 'Documents'),
  List<JobStatusHistoryEntry>? history,
  String? pickupAddress = '15 Kasr El Nil St, Downtown',
  String? dropAddress = '4 Tahrir St, Dokki',
  String? pickupNote = 'Floor 3',
  String? dropNote = 'Beside the metro',
}) {
  DateTime ago(int m) => fixedNow.subtract(Duration(minutes: m));
  return Job(
    id: 'a1b2c3d4e5f6',
    ownerId: 'tenant-svc-1',
    employeeId: 'emp-1',
    userId: 'user-1',
    serviceId: 'svc-1',
    status: status,
    subStatus: subStatus,
    location: JobLocation(
        latitude: 30.05,
        longitude: 31.24,
        address: pickupAddress,
        addressNote: pickupNote),
    destination: JobLocation(
        latitude: 30.06,
        longitude: 31.22,
        address: dropAddress,
        addressNote: dropNote),
    paymentMethod: 'cod',
    suggestedPrice: 42,
    agreedPrice: 45,
    createdAt: ago(30),
    statusHistory: history ??
        [
          JobStatusHistoryEntry(status: 'pending_dispatch', at: ago(30)),
          JobStatusHistoryEntry(
              status: 'active', subStatus: 'heading_to_pickup', at: ago(28)),
          if (subStatus == 'picked_up' || status == 'completed')
            JobStatusHistoryEntry(
                status: 'active', subStatus: 'picked_up', at: ago(6)),
          if (status == 'completed')
            JobStatusHistoryEntry(status: 'completed', at: ago(1)),
        ],
    estimatedDurationMinutes: etaMinutes,
    recipient: recipient,
    packageDetails: package,
    courierPhone: courierPhone,
  );
}
