import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/providers/map_tracking_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  group('F-02: Availability heartbeat does not clobber active job on owner map',
      () {
    test(
        'Repro F-02: Heartbeat ping with null/empty job_id must not wipe existing active job association',
        () {
      final apiClient = ApiClient();
      final mapProvider = MapTrackingProvider(apiClient);

      // Courier emp-101 has an active job on the owner fleet map
      mapProvider.updateMarkerManually(EmployeeMarkerData(
        employeeId: 'emp-101',
        jobId: 'job-in-transit-555',
        latitude: 30.0444,
        longitude: 31.2357,
        updatedAt: DateTime.now(),
      ));

      expect(mapProvider.employeeMarkers['emp-101']?.jobId,
          equals('job-in-transit-555'));

      // Simulate a periodic availability heartbeat payload received from WebSocket
      // Notice: availability heartbeat pings may contain 'job_id': null or 'job_id': ''
      final heartbeatData = jsonEncode({
        'type': 'location_update',
        'employee_id': 'emp-101',
        'latitude': 30.0450,
        'longitude': 31.2360,
        'job_id': null,
      });

      // Deliver via the provider's data handler
      mapProvider.handleIncomingDataForTest(heartbeatData);

      final markerAfterHeartbeat = mapProvider.employeeMarkers['emp-101'];
      expect(markerAfterHeartbeat, isNotNull);

      // F-02 Assertion: Heartbeat must NOT wipe the courier's active job association!
      if (markerAfterHeartbeat!.jobId == null) {
        fail(
            'F-02 REPRO FAILED (BUG CONFIRMED): Availability heartbeat wiped active job association on owner map! Courier is now marked Idle instead of On Route.');
      }
      expect(markerAfterHeartbeat.jobId, equals('job-in-transit-555'));
    });
  });
}
