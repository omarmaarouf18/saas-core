import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';

class MockSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEmployeeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  UserProfile? user = UserProfile(
    id: 'emp-avail-1',
    email: 'courier@test.com',
    username: 'Speedy Courier',
    role: 'employee',
    kycStatus: 'approved',
    kyeStatus: 'approved',
  );

  @override
  String? token = 'courier-mock-token';

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchUserProfile() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEmployeeJobsProvider extends ChangeNotifier
    implements EmployeeJobsProvider {
  @override
  List<Job> jobs = [];

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchAssignedJobs(String token) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotificationsProvider extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildTestWidget({
  required EmployeeLocationProvider locationProvider,
  required FakeEmployeeJobsProvider jobsProvider,
  Locale locale = const Locale('en'),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => FakeEmployeeAuthProvider(),
      ),
      ChangeNotifierProvider<EmployeeJobsProvider>.value(
        value: jobsProvider,
      ),
      ChangeNotifierProvider<EmployeeLocationProvider>.value(
        value: locationProvider,
      ),
      ChangeNotifierProvider<NotificationsProvider>(
        create: (_) => FakeNotificationsProvider(),
      ),
      ChangeNotifierProvider<ChatProvider>(
        create: (_) => FakeChatProvider(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
      ],
      home: const Scaffold(
        body: EmployeeJobsScreen(isEmbeddedInTab: true),
      ),
    ),
  );
}

void main() {
  group('GAP-04: Courier Availability Toggle & Provider Unit Tests', () {
    late MockSecureStorage mockStorage;
    late EmployeeLocationProvider locationProvider;
    late ApiClient apiClient;

    setUp(() {
      mockStorage = MockSecureStorage();
      apiClient = ApiClient(baseUrl: 'http://localhost:8080');
      locationProvider = EmployeeLocationProvider(
        apiClient,
        storage: mockStorage,
      );
    });

    test('Initial availability defaults to true (online)', () {
      expect(locationProvider.isAvailableOnline, isTrue);
    });

    test('setAvailableOnline persists to storage and notifies listeners',
        () async {
      bool notified = false;
      locationProvider.addListener(() {
        notified = true;
      });

      await locationProvider.setAvailableOnline(false);
      expect(locationProvider.isAvailableOnline, isFalse);
      expect(notified, isTrue);
      expect(mockStorage._data['courier_available_online'], 'false');

      await locationProvider.setAvailableOnline(true);
      expect(locationProvider.isAvailableOnline, isTrue);
      expect(mockStorage._data['courier_available_online'], 'true');
    });

    test('Restores persisted offline state from storage on construction',
        () async {
      mockStorage._data['courier_available_online'] = 'false';
      final restoredProvider = EmployeeLocationProvider(
        apiClient,
        storage: mockStorage,
      );

      // Allow microtask _loadSavedAvailability to complete
      await Future<void>.delayed(Duration.zero);
      expect(restoredProvider.isAvailableOnline, isFalse);
    });

    test('startAvailabilityTracking is suppressed when courier is offline',
        () async {
      await locationProvider.setAvailableOnline(false);
      await locationProvider.startAvailabilityTracking('dummy-token');

      // Provider should remain not tracking and not available
      expect(locationProvider.isAvailable, isFalse);
      expect(locationProvider.isTracking, isFalse);
    });
  });

  group('GAP-04: Courier Availability Switch Widget Tests', () {
    late MockSecureStorage mockStorage;
    late EmployeeLocationProvider locationProvider;
    late FakeEmployeeJobsProvider jobsProvider;
    late ApiClient apiClient;

    setUp(() {
      mockStorage = MockSecureStorage();
      apiClient = ApiClient(baseUrl: 'http://localhost:8080');
      locationProvider = EmployeeLocationProvider(
        apiClient,
        storage: mockStorage,
      );
      jobsProvider = FakeEmployeeJobsProvider();
    });

    testWidgets(
        'Renders availability card and switch in Online state by default',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        locationProvider: locationProvider,
        jobsProvider: jobsProvider,
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('courier_availability_card')), findsOneWidget);
      final switchFinder = find.byKey(const Key('courier_availability_switch'));
      expect(switchFinder, findsOneWidget);

      final Switch switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isTrue);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Accepting new delivery requests'), findsOneWidget);
    });

    testWidgets('Toggling switch sets courier offline and updates UI labels',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        locationProvider: locationProvider,
        jobsProvider: jobsProvider,
      ));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('courier_availability_switch'));
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(locationProvider.isAvailableOnline, isFalse);
      expect(mockStorage._data['courier_available_online'], 'false');

      final Switch switchWidget = tester.widget<Switch>(switchFinder);
      expect(switchWidget.value, isFalse);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Not accepting new delivery requests'), findsOneWidget);
    });

    testWidgets(
        'Switch is disabled and shows active job lock text when courier has an active job',
        (tester) async {
      jobsProvider.jobs = [
        Job(
          id: 'job-active-1',
          userId: 'user-1',
          ownerId: 'owner-1',
          serviceId: 'srv-1',
          status: 'active',
          paymentMethod: 'wallet',
          lockedEscrowAmount: 25.0,
          location: JobLocation(latitude: 30.0, longitude: 31.0),
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        locationProvider: locationProvider,
        jobsProvider: jobsProvider,
      ));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const Key('courier_availability_switch'));
      expect(switchFinder, findsOneWidget);

      final Switch switchWidget = tester.widget<Switch>(switchFinder);
      // Switch onChanged must be null (disabled)
      expect(switchWidget.onChanged, isNull);
      expect(
          find.text('Availability locked during active job'), findsOneWidget);
    });

    testWidgets('Renders properly in Egyptian Arabic (RTL)', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        locationProvider: locationProvider,
        jobsProvider: jobsProvider,
        locale: const Locale('ar'),
      ));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('courier_availability_card')), findsOneWidget);
      expect(find.text('متصل'), findsOneWidget);
      expect(find.text('جاهز لاستلام طلبات توصيل جديدة'), findsOneWidget);
    });
  });
}
