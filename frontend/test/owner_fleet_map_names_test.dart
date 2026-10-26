import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/providers/map_tracking_provider.dart';

EmployeeMarkerData _marker(String employeeId, {String? jobId}) =>
    EmployeeMarkerData(
      employeeId: employeeId,
      jobId: jobId,
      latitude: 30.0444,
      longitude: 31.2357,
      updatedAt: DateTime(2026, 9, 1, 8, 0, 0),
    );

void main() {

  group('MapTrackingProvider name lookup', () {
    test('Backfills existing markers and applies to later updates', () async {
      final provider = MapTrackingProvider(ApiClient());
      provider.updateMarkerManually(_marker('emp-9'));

      provider.setEmployeeNameLookup({'emp-9': 'Ziad Courier'});
      expect(provider.markersList.single.employeeName, 'Ziad Courier');

      // Roster change clears names that no longer match.
      provider.setEmployeeNameLookup(const {});
      expect(provider.markersList.single.employeeName, isNull);

      // Lookup stored for markers created afterwards (live heartbeats).
      provider.setEmployeeNameLookup({'emp-9': 'Ziad Courier'});
      provider.handleIncomingDataForTest(
        '{"type":"location_update","employee_id":"emp-9","latitude":30.05,"longitude":31.24,"job_id":"job-2"}',
      );
      final updated = provider.markersList.single;
      expect(updated.employeeName, 'Ziad Courier');
      expect(updated.jobId, 'job-2');
    });
  });
}
