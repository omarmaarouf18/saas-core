import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/map_tracking_provider.dart';

class MockMapTrackingProvider extends MapTrackingProvider {
  final Map<String, EmployeeMarkerData> initialMarkers;
  final bool initialLoading;
  final bool initialConnected;
  final String? initialSubError;
  final String? initialError;
  final JobLocation? initialJobLoc;
  final JobLocation? initialJobDestination;
  final String? initialAssignedEmp;

  MockMapTrackingProvider({
    required ApiClient apiClient,
    this.initialMarkers = const {},
    this.initialLoading = false,
    this.initialConnected = true,
    this.initialSubError,
    this.initialError,
    this.initialJobLoc,
    this.initialJobDestination,
    this.initialAssignedEmp,
  }) : super(apiClient) {
    _testMarkers = Map.from(initialMarkers);
    _testLoading = initialLoading;
    _testConnected = initialConnected;
    _testSubError = initialSubError;
    _testError = initialError;
    _testJobLoc = initialJobLoc;
    _testJobDestination = initialJobDestination;
    _testAssignedEmp = initialAssignedEmp;
  }

  late Map<String, EmployeeMarkerData> _testMarkers;
  late bool _testLoading;
  late bool _testConnected;
  late String? _testSubError;
  late String? _testError;
  late JobLocation? _testJobLoc;
  late JobLocation? _testJobDestination;
  late String? _testAssignedEmp;
  bool hydrateOwnerFleetCalled = false;

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
  String? get error => _testError;

  @override
  JobLocation? get customerJobLocation => _testJobLoc;

  @override
  JobLocation? get customerJobDestination => _testJobDestination;

  @override
  String? get assignedEmployeeId => _testAssignedEmp;

  @override
  Future<void> hydrateOwnerFleet(String ownerToken) async {
    hydrateOwnerFleetCalled = true;
  }

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
  bool shouldFail = false;

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    getCalledEndpoints.add(endpoint);
    if (shouldFail) {
      throw ApiClientException('Network failure', statusCode: 500);
    }
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


  group('MapTrackingProvider Unit Tests', () {
    test('(d) hydrateCustomerJob stores pickup and destination locations',
        () async {
      final mockApi = _MockApiClientForMap();
      mockApi.getResponses['/users/jobs/get'] = {
        'id': 'job-999',
        'employee_id': 'courier-77',
        'location': {'latitude': 30.0, 'longitude': 30.0},
        'destination': {'latitude': 30.1, 'longitude': 30.1},
      };

      final provider = MapTrackingProvider(mockApi);
      await provider.hydrateCustomerJob('job-999', 'token-999');

      expect(provider.customerJobLocation?.latitude, 30.0);
      expect(provider.customerJobDestination?.latitude, 30.1);
      expect(provider.customerJobDestination?.longitude, 30.1);
      expect(provider.assignedEmployeeId, 'courier-77');
    });

    test('(f) hydrateCustomerJob tolerates a null destination', () async {
      final mockApi = _MockApiClientForMap();
      mockApi.getResponses['/users/jobs/get'] = {
        'id': 'job-1000',
        'employee_id': 'courier-78',
        'location': {'latitude': 30.0, 'longitude': 30.0},
      };

      final provider = MapTrackingProvider(mockApi);
      await provider.hydrateCustomerJob('job-1000', 'token-1000');

      expect(provider.customerJobLocation?.latitude, 30.0);
      expect(provider.customerJobDestination, isNull);
    });

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

    test(
        '(e16) hydrateOwnerFleet retains existing markers during revalidation failure (audit E16)',
        () async {
      final mockApi = _MockApiClientForMap();
      mockApi.getResponses['/users/employees/available'] = {
        'count': 1,
        'employees': [
          {
            'employee_id': 'emp-existing',
            'latitude': 30.01,
            'longitude': 31.01,
            'updated_at': '2026-09-05T08:00:00Z',
          }
        ]
      };
      mockApi.getResponses['/users/jobs/owner'] = [];

      final provider = MapTrackingProvider(mockApi);
      await provider.hydrateOwnerFleet('owner-token-1');
      expect(provider.employeeMarkers.containsKey('emp-existing'), isTrue);

      // Now simulate network failure on subsequent revalidation
      mockApi.shouldFail = true;
      await provider.hydrateOwnerFleet('owner-token-1');

      // Stale marker is retained
      expect(provider.employeeMarkers.containsKey('emp-existing'), isTrue);
      expect(provider.error, isNotNull);
    });
  });
}
