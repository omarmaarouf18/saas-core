import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/screens/owner_fleet_map_screen.dart';
import 'package:frontend/screens/customer_job_map_screen.dart';

class MockMapTrackingProvider extends MapTrackingProvider {
  final Map<String, EmployeeMarkerData> initialMarkers;
  final bool initialLoading;
  final bool initialConnected;
  final String? initialSubError;
  final JobLocation? initialJobLoc;
  final String? initialAssignedEmp;

  MockMapTrackingProvider({
    required ApiClient apiClient,
    this.initialMarkers = const {},
    this.initialLoading = false,
    this.initialConnected = true,
    this.initialSubError,
    this.initialJobLoc,
    this.initialAssignedEmp,
  }) : super(apiClient) {
    initialMarkers.forEach((k, v) {
      updateMarkerManually(v);
    });
  }

  @override
  JobLocation? get customerJobLocation => initialJobLoc;

  @override
  String? get assignedEmployeeId => initialAssignedEmp;

  @override
  bool get isLoading => initialLoading;

  @override
  bool get isConnected => initialConnected;

  @override
  String? get subscriptionError => initialSubError;

  @override
  Future<void> hydrateOwnerFleet(String ownerToken) async {
    // Prevent real network call during widget unit testing
  }

  @override
  Future<void> hydrateCustomerJob(String jobId, String userToken) async {
    // Prevent real network call during widget unit testing
  }

  @override
  void connectAndSubscribe(String channel, String token,
      {dynamic customChannel}) {
    // Prevent real WebSocket network connection during unit testing
  }
}

void main() {
  final apiClient = ApiClient();

  group('OwnerFleetMapScreen Tests', () {
    testWidgets('(c) Loading state before first data arrives',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialLoading: true,
        initialConnected: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const OwnerFleetMapScreen(
              ownerId: 'owner-123',
              token: 'token-123',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('fleet_map_loading')), findsOneWidget);
    });

    testWidgets('(a) Initial marker render from hydration response',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialMarkers: {
          'emp-001': EmployeeMarkerData(
            employeeId: 'emp-001',
            jobId: 'job-100',
            latitude: 30.0444,
            longitude: 31.2357,
            updatedAt: DateTime.now(),
          ),
        },
        initialLoading: false,
        initialConnected: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const OwnerFleetMapScreen(
              ownerId: 'owner-123',
              token: 'token-123',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Fleet Live Map'), findsOneWidget);
      expect(find.text('emp-001'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('(b) Marker position update on simulated location_update message',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialMarkers: {
          'emp-001': EmployeeMarkerData(
            employeeId: 'emp-001',
            jobId: 'job-100',
            latitude: 30.0444,
            longitude: 31.2357,
            updatedAt: DateTime.now(),
          ),
        },
        initialLoading: false,
        initialConnected: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const OwnerFleetMapScreen(
              ownerId: 'owner-123',
              token: 'token-123',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('emp-001'), findsOneWidget);

      // Simulate incoming location update event for emp-001 & emp-002
      mockProvider.updateMarkerManually(
        EmployeeMarkerData(
          employeeId: 'emp-001',
          jobId: 'job-100',
          latitude: 30.0445,
          longitude: 31.2358,
          updatedAt: DateTime.now(),
        ),
      );
      mockProvider.updateMarkerManually(
        EmployeeMarkerData(
          employeeId: 'emp-002',
          jobId: 'job-101',
          latitude: 30.0450,
          longitude: 31.2360,
          updatedAt: DateTime.now(),
        ),
      );

      await tester.pump();

      expect(find.text('emp-001'), findsOneWidget);
      expect(find.text('emp-002'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    });
  });

  group('CustomerJobMapScreen Tests', () {
    testWidgets('(c) Loading state before first data arrives',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialLoading: true,
        initialConnected: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const CustomerJobMapScreen(
              jobId: 'job-999',
              token: 'token-999',
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('customer_job_map_loading')), findsOneWidget);
    });

    testWidgets('(a) Initial marker render from hydration response',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialAssignedEmp: 'courier-77',
        initialJobLoc: JobLocation(latitude: 30.0, longitude: 30.0),
        initialMarkers: {
          'courier-77': EmployeeMarkerData(
            employeeId: 'courier-77',
            jobId: 'job-999',
            latitude: 30.01,
            longitude: 30.01,
            updatedAt: DateTime.now(),
          ),
        },
        initialLoading: false,
        initialConnected: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const CustomerJobMapScreen(
              jobId: 'job-999',
              token: 'token-999',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Live Courier Tracking'), findsOneWidget);
      expect(find.text('courier-77'), findsOneWidget);
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
      expect(find.byIcon(Icons.flag), findsOneWidget);
    });

    testWidgets('(b) Marker position update on simulated location_update message',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialAssignedEmp: 'courier-77',
        initialMarkers: {
          'courier-77': EmployeeMarkerData(
            employeeId: 'courier-77',
            jobId: 'job-999',
            latitude: 30.01,
            longitude: 30.01,
            updatedAt: DateTime.now(),
          ),
        },
        initialLoading: false,
        initialConnected: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const CustomerJobMapScreen(
              jobId: 'job-999',
              token: 'token-999',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Simulate incoming courier position movement
      mockProvider.updateMarkerManually(
        EmployeeMarkerData(
          employeeId: 'courier-77',
          jobId: 'job-999',
          latitude: 30.03,
          longitude: 30.03,
          updatedAt: DateTime.now(),
        ),
      );

      await tester.pump();

      expect(find.text('courier-77'), findsOneWidget);
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    });
  });
}
