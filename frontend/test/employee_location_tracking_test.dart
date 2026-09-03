import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';

class MockGeolocatorPlatformForTracking extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  bool isServiceEnabled = true;
  LocationPermission initialPermission = LocationPermission.whileInUse;
  final StreamController<Position> positionStreamController =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => isServiceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => initialPermission;

  @override
  Future<LocationPermission> requestPermission() async => initialPermission;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return positionStreamController.stream;
  }
}

class MockApiClientForTracking extends ApiClient {
  int postCallCount = 0;
  List<String> postEndpoints = [];
  List<Map<String, dynamic>> postPayloads = [];
  bool shouldThrow429 = false;
  bool shouldThrowImplausibleSpeed = false;
  bool shouldThrow500 = false;

  @override
  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? queryParams,
      Map<String, String>? headers,
      bool isRetry = false}) async {
    postCallCount++;
    postEndpoints.add(endpoint);
    postPayloads.add(body);

    if (shouldThrow429) {
      throw ApiClientException(
          'Too many location updates. Minimum interval is 3 seconds.',
          statusCode: 429);
    }

    if (shouldThrowImplausibleSpeed) {
      throw ApiClientException('implausible_speed: speed exceeds max limit',
          statusCode: 400);
    }

    if (shouldThrow500) {
      throw ApiClientException('Internal Server Error', statusCode: 500);
    }

    return {'message': 'location updated'};
  }
}

class MockAuthProviderForTest extends AuthProvider {
  final UserProfile? mockUser;
  final String? mockToken;
  MockAuthProviderForTest(super.apiClient,
      {this.mockUser, this.mockToken = 'test-token'});

  @override
  UserProfile? get user => mockUser;

  @override
  String? get token => mockToken;
}

class MockEmployeeJobsProviderForTest extends EmployeeJobsProvider {
  final List<Job> mockJobs;
  MockEmployeeJobsProviderForTest(super.apiClient, {this.mockJobs = const []});

  @override
  List<Job> get jobs => mockJobs;

  @override
  Future<void> fetchAssignedJobs(String token) async {}
}

Position createPosition(double lat, double lng) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.now(),
    accuracy: 5.0,
    altitude: 0.0,
    altitudeAccuracy: 0.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: 10.0,
    speedAccuracy: 1.0,
  );
}

void main() {
  late MockGeolocatorPlatformForTracking mockGeolocator;
  late MockApiClientForTracking mockApiClient;
  late EmployeeLocationProvider locationProvider;

  setUp(() {
    mockGeolocator = MockGeolocatorPlatformForTracking();
    GeolocatorPlatform.instance = mockGeolocator;
    mockApiClient = MockApiClientForTracking();
    locationProvider = EmployeeLocationProvider(
      mockApiClient,
      geolocator: mockGeolocator,
    );
  });

  tearDown(() async {
    await locationProvider.stopTracking();
    locationProvider.dispose();
  });

  test(
      '(a) Provider throttles actual POST calls to no more than 1 per 3.5s when stream fires rapidly',
      () async {
    await locationProvider.startTracking('job-101', 'token-emp-1');
    expect(locationProvider.isTracking, isTrue);

    // Emit 3 position updates rapidly
    mockGeolocator.positionStreamController.add(createPosition(30.01, 31.01));
    await Future.delayed(const Duration(milliseconds: 50));
    mockGeolocator.positionStreamController.add(createPosition(30.02, 31.02));
    await Future.delayed(const Duration(milliseconds: 50));
    mockGeolocator.positionStreamController.add(createPosition(30.03, 31.03));
    await Future.delayed(const Duration(milliseconds: 50));

    // Only the 1st position should trigger a POST call due to the 3.5s minimum interval gate
    expect(mockApiClient.postCallCount, equals(1));
    expect(mockApiClient.postPayloads.first['job_id'], equals('job-101'));
  });

  test(
      '(b) 429 rate limit and implausible_speed 400 responses log quietly without setting visible error state',
      () async {
    mockApiClient.shouldThrow429 = true;
    await locationProvider.startTracking('job-102', 'token-emp-1');

    mockGeolocator.positionStreamController.add(createPosition(30.05, 31.05));
    await Future.delayed(const Duration(milliseconds: 50));

    // Status remains tracking and error is null
    expect(locationProvider.status, equals(LocationSharingStatus.tracking));
    expect(locationProvider.error, isNull);

    // Test implausible speed
    mockApiClient.shouldThrow429 = false;
    mockApiClient.shouldThrowImplausibleSpeed = true;

    // Reset lastSentTime throttle for testing
    await locationProvider.stopTracking();
    await locationProvider.startTracking('job-102', 'token-emp-1');

    mockGeolocator.positionStreamController.add(createPosition(30.06, 31.06));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(locationProvider.status, equals(LocationSharingStatus.tracking));
    expect(locationProvider.error, isNull);
  });

  test('(c) Genuine failures (e.g. 500) set a visible friendly error',
      () async {
    mockApiClient.shouldThrow500 = true;
    await locationProvider.startTracking('job-103', 'token-emp-1');

    mockGeolocator.positionStreamController.add(createPosition(30.10, 31.10));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(locationProvider.status, equals(LocationSharingStatus.error));
    expect(locationProvider.error, equals(ErrorMessages.serverError));
  });

  test(
      '(d) stopTracking() cancels underlying stream subscription (no further POSTs after stop)',
      () async {
    await locationProvider.startTracking('job-104', 'token-emp-1');

    mockGeolocator.positionStreamController.add(createPosition(30.15, 31.15));
    await Future.delayed(const Duration(milliseconds: 50));
    expect(mockApiClient.postCallCount, equals(1));

    await locationProvider.stopTracking();
    expect(locationProvider.status, equals(LocationSharingStatus.idle));

    // Emit another position after stop
    mockGeolocator.positionStreamController.add(createPosition(30.16, 31.16));
    await Future.delayed(const Duration(milliseconds: 50));

    // POST count remains 1
    expect(mockApiClient.postCallCount, equals(1));
  });

  testWidgets(
      '(e) EmployeeJobsScreen shows permission-denied explanation UI when denied and sharing indicator when tracking',
      (WidgetTester tester) async {
    final activeJob = Job(
      id: 'job-active-200',
      ownerId: 'owner-1',
      employeeId: 'emp-1',
      userId: 'cust-1',
      serviceId: 'service-1',
      status: 'active',
      location: JobLocation(latitude: 30.0, longitude: 31.0),
      paymentMethod: 'cod',
      lockedEscrowAmount: 25.0,
    );

    final apiClient = ApiClient();
    final authProvider = MockAuthProviderForTest(
      apiClient,
      mockUser: UserProfile(
        id: 'emp-1',
        email: 'driver@example.com',
        username: 'DriverUser',
        role: 'employee',
      ),
    );
    final jobsProvider = MockEmployeeJobsProviderForTest(
      apiClient,
      mockJobs: [activeJob],
    );

    // Scenario 1: Permission denied
    mockGeolocator.initialPermission = LocationPermission.denied;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<EmployeeJobsProvider>.value(
                value: jobsProvider),
            ChangeNotifierProvider<EmployeeLocationProvider>.value(
                value: locationProvider),
            ChangeNotifierProvider<NotificationsProvider>(
                create: (_) => NotificationsProvider(apiClient)),
          ],
          child: const EmployeeJobsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger tracking start with denied permission
    await locationProvider.startTracking(activeJob.id, 'test-token');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_permission_denied_banner')),
        findsOneWidget);
    expect(find.byKey(const Key('open_app_settings_button')), findsOneWidget);
    expect(
        find.text(
            'Location sharing is required to share your live delivery progress with the customer.'),
        findsOneWidget);

    // Scenario 2: Permission granted & tracking active
    mockGeolocator.initialPermission = LocationPermission.whileInUse;
    await locationProvider.startTracking(activeJob.id, 'test-token');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location_sharing_indicator')), findsOneWidget);
    expect(find.text('Sharing live location'), findsOneWidget);
  });

  test(
      '(f) startAvailabilityTracking sends pings to /users/employee/location without job_id',
      () async {
    await locationProvider.startAvailabilityTracking('token-emp-1');
    expect(locationProvider.isTracking, isTrue);
    expect(locationProvider.isAvailable, isTrue);
    expect(locationProvider.activeJobId, isNull);

    mockGeolocator.positionStreamController.add(createPosition(30.01, 31.01));
    await Future.delayed(const Duration(milliseconds: 50));

    expect(mockApiClient.postCallCount, equals(1));
    expect(
        mockApiClient.postEndpoints.first, equals('/users/employee/location'));
    expect(mockApiClient.postPayloads.first['requester_token'],
        equals('token-emp-1'));
    expect(mockApiClient.postPayloads.first.containsKey('job_id'), isFalse);
  });
}
