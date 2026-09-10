import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  final Position _currentPosition = Position(
    latitude: 30.0444,
    longitude: 31.2357,
    timestamp: DateTime.now(),
    accuracy: 5.0,
    altitude: 0.0,
    altitudeAccuracy: 0.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    return _currentPosition;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return Stream.value(_currentPosition);
  }
}

class _MockAuthProvider extends AuthProvider {
  _MockAuthProvider(super.apiClient) {
    // Authenticated employee
  }

  @override
  UserProfile? get user => UserProfile(
        id: 'emp-101',
        email: 'emp@test.com',
        username: 'Courier101',
        role: 'employee',
      );

  @override
  String? get token => 'test-emp-jwt-token';
}

class _MockJobsProvider extends EmployeeJobsProvider {
  final List<Job> _testJobs;

  _MockJobsProvider(super.apiClient, this._testJobs);

  @override
  List<Job> get jobs => _testJobs;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

class _MockApiClientForTracking extends ApiClient {
  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    return {'message': 'location updated'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
      'F-01: Live tracking lifecycle on navigation away from EmployeeJobsScreen',
      () {
    testWidgets(
        'Repro F-01: Live tracking must survive navigation away from EmployeeJobsScreen during an active job',
        (WidgetTester tester) async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform();

      final apiClient = _MockApiClientForTracking();
      final auth = _MockAuthProvider(apiClient);
      final activeJob = Job(
        id: 'job-active-live-tracking',
        ownerId: 'owner-1',
        employeeId: 'emp-101',
        userId: 'cust-1',
        serviceId: 'service-1',
        status: 'active',
        location: JobLocation(latitude: 30.0444, longitude: 31.2357),
        paymentMethod: 'cod',
      );

      final jobsProvider = _MockJobsProvider(apiClient, [activeJob]);
      final locationProvider = EmployeeLocationProvider(apiClient);

      // Start active tracking for the active job
      await locationProvider.startTracking(activeJob.id, auth.token!);
      expect(locationProvider.isTracking, isTrue,
          reason:
              'Precondition: locationProvider must be tracking for active job');
      expect(locationProvider.activeJobId, equals(activeJob.id));

      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<EmployeeJobsProvider>.value(
                value: jobsProvider),
            ChangeNotifierProvider<EmployeeLocationProvider>.value(
                value: locationProvider),
            ChangeNotifierProvider<NotificationsProvider>(
                create: (_) => NotificationsProvider(apiClient)),
          ],
          child: MaterialApp(
            navigatorKey: navKey,
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const EmployeeJobsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Confirm EmployeeJobsScreen is rendered and tracking is active
      expect(find.byType(EmployeeJobsScreen), findsOneWidget);
      expect(locationProvider.isTracking, isTrue);

      // Simulate courier navigating away (e.g. to Chat or Notifications)
      navKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Text('Chat Screen Navigation'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On another screen now
      expect(find.text('Chat Screen Navigation'), findsOneWidget);

      // F-01 Assertion: Live tracking MUST CONTINUE during active delivery even when on another screen!
      if (!locationProvider.isTracking) {
        fail(
            'F-01 REPRO FAILED (BUG CONFIRMED): Live tracking was killed when courier navigated away from EmployeeJobsScreen! isTracking=false, activeJobId=${locationProvider.activeJobId}');
      }
      expect(locationProvider.isTracking, isTrue);
      expect(locationProvider.activeJobId, equals(activeJob.id));
    });
  });

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
