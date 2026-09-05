import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
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
    _testMarkers = Map.from(initialMarkers);
    _testLoading = initialLoading;
    _testConnected = initialConnected;
    _testSubError = initialSubError;
    _testJobLoc = initialJobLoc;
    _testAssignedEmp = initialAssignedEmp;
  }

  late Map<String, EmployeeMarkerData> _testMarkers;
  late bool _testLoading;
  late bool _testConnected;
  late String? _testSubError;
  late JobLocation? _testJobLoc;
  late String? _testAssignedEmp;

  @override
  Map<String, EmployeeMarkerData> get employeeMarkers =>
      Map.unmodifiable(_testMarkers);

  @override
  List<EmployeeMarkerData> get markersList => _testMarkers.values.toList();

  @override
  bool get isLoading => _testLoading;

  @override
  bool get isConnected => _testConnected;

  @override
  String? get subscriptionError => _testSubError;

  @override
  JobLocation? get customerJobLocation => _testJobLoc;

  @override
  String? get assignedEmployeeId => _testAssignedEmp;

  @override
  Future<void> hydrateOwnerFleet(String ownerToken) async {}

  @override
  Future<void> hydrateCustomerJob(String jobId, String userToken) async {}

  @override
  void connectAndSubscribe(String channel, String token,
      {dynamic customChannel}) {}

  @override
  Future<void> disconnect() async {}

  @override
  void updateMarkerManually(EmployeeMarkerData data) {
    _testMarkers[data.employeeId] = data;
    notifyListeners();
  }
}

class _MockApiClientForMap extends ApiClient {
  final Map<String, dynamic> getResponses = {};
  final List<String> getCalledEndpoints = [];

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    getCalledEndpoints.add(endpoint);
    if (getResponses.containsKey(endpoint)) {
      return getResponses[endpoint];
    }
    return [];
  }
}

Widget buildTestMapApp({required Widget child}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
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

    testWidgets(
        '(b) Marker position update on simulated location_update message',
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
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
          latitude: 30.0500,
          longitude: 31.2400,
          updatedAt: DateTime.now(),
        ),
      );
      mockProvider.updateMarkerManually(
        EmployeeMarkerData(
          employeeId: 'emp-002',
          jobId: 'job-101',
          latitude: 30.0600,
          longitude: 31.2500,
          updatedAt: DateTime.now(),
        ),
      );

      await tester.pump();

      expect(find.text('emp-001'), findsOneWidget);
      expect(find.text('emp-002'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    });

    testWidgets(
        '(d) Available (idle) courier markers render distinctly and filter pills switch views',
        (WidgetTester tester) async {
      final mockProvider = MockMapTrackingProvider(
        apiClient: apiClient,
        initialMarkers: {
          'emp-on-job': EmployeeMarkerData(
            employeeId: 'emp-on-job',
            jobId: 'job-active-1',
            latitude: 30.0444,
            longitude: 31.2357,
            updatedAt: DateTime.now(),
          ),
          'emp-idle': EmployeeMarkerData(
            employeeId: 'emp-idle',
            jobId: null, // Idle / available!
            latitude: 30.0500,
            longitude: 31.2400,
            updatedAt: DateTime.now(),
          ),
        },
        initialLoading: false,
        initialConnected: true,
      );

      await tester.pumpWidget(
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const OwnerFleetMapScreen(
              ownerId: 'owner-123',
              token: 'token-123',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Both markers should be visible in 'All Fleet' view
      expect(find.text('emp-on-job'), findsOneWidget);
      expect(find.text('emp-idle'), findsOneWidget);

      // Tap 'On Route' pill
      await tester.tap(find.text('On Route'));
      await tester.pumpAndSettle();

      expect(find.text('emp-on-job'), findsOneWidget);
      expect(find.text('emp-idle'), findsNothing);

      // Tap 'Idle' pill
      await tester.tap(find.text('Idle'));
      await tester.pumpAndSettle();

      expect(find.text('emp-on-job'), findsNothing);
      expect(find.text('emp-idle'), findsOneWidget);

      // Tap on idle driver marker to view driver card
      await tester.tap(find.text('emp-idle'));
      await tester.pumpAndSettle();

      // Should show 'emp-idle' on both marker and card
      expect(find.text('emp-idle'), findsNWidgets(2));
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
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

    testWidgets(
        '(b) Marker position update on simulated location_update message',
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
        buildTestMapApp(
          child: ChangeNotifierProvider<MapTrackingProvider>.value(
            value: mockProvider,
            child: const CustomerJobMapScreen(
              jobId: 'job-999',
              token: 'token-999',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('courier-77'), findsOneWidget);

      // Simulate position update
      mockProvider.updateMarkerManually(
        EmployeeMarkerData(
          employeeId: 'courier-77',
          jobId: 'job-999',
          latitude: 30.02,
          longitude: 30.02,
          updatedAt: DateTime.now(),
        ),
      );
      await tester.pump();

      expect(find.text('courier-77'), findsOneWidget);
      expect(find.byIcon(Icons.directions_bike), findsOneWidget);
    });
  });

  group('MapTrackingProvider Unit Tests', () {
    test(
        '(e) hydrateOwnerFleet queries both /users/employees/available and /users/jobs/owner',
        () async {
      final mockApi = _MockApiClientForMap();
      mockApi.getResponses['/users/employees/available'] = {
        'count': 1,
        'employees': [
          {
            'employee_id': 'emp-available-1',
            'latitude': 30.01,
            'longitude': 31.01,
            'updated_at': '2026-09-05T08:00:00Z',
          }
        ]
      };
      mockApi.getResponses['/users/jobs/owner'] = [
        {
          'id': 'job-active-1',
          'employee_id': 'emp-active-1',
          'status': 'active',
          'location': {'latitude': 30.05, 'longitude': 31.05},
          'updated_at': '2026-09-05T08:00:00Z',
        }
      ];

      final provider = MapTrackingProvider(mockApi);
      await provider.hydrateOwnerFleet('owner-token-1');

      expect(
          mockApi.getCalledEndpoints, contains('/users/employees/available'));
      expect(mockApi.getCalledEndpoints, contains('/users/jobs/owner'));

      // Both markers should be in employeeMarkers
      expect(provider.employeeMarkers.containsKey('emp-available-1'), isTrue);
      expect(provider.employeeMarkers['emp-available-1']!.jobId, isNull);

      expect(provider.employeeMarkers.containsKey('emp-active-1'), isTrue);
      expect(provider.employeeMarkers['emp-active-1']!.jobId,
          equals('job-active-1'));
    });
  });
}
