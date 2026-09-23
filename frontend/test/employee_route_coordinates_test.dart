import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';

class _MockAuth extends AuthProvider {
  _MockAuth(super.apiClient);
  @override
  UserProfile? get user => UserProfile(
        id: 'emp-1',
        email: 'employee@example.com',
        username: 'EmployeeUser',
        role: 'employee',
      );
  @override
  String? get token => 'test-token';
}

class _MockJobs extends EmployeeJobsProvider {
  final List<Job> initialJobs;
  _MockJobs(super.apiClient, {this.initialJobs = const []});

  @override
  List<Job> get jobs => List.unmodifiable(initialJobs);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

Widget _buildApp(EmployeeJobsProvider jobsProvider) {
  final apiClient = ApiClient();
  return MaterialApp(
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
        ChangeNotifierProvider<AuthProvider>.value(value: _MockAuth(apiClient)),
        ChangeNotifierProvider<EmployeeJobsProvider>.value(value: jobsProvider),
        ChangeNotifierProvider<EmployeeLocationProvider>(
            create: (_) => EmployeeLocationProvider(apiClient)),
        ChangeNotifierProvider<NotificationsProvider>(
            create: (_) => NotificationsProvider(apiClient)),
      ],
      child: const EmployeeJobsScreen(),
    ),
  );
}

void main() {
  test('JobLocation.formatCoordinates renders 4-decimal lat/lon pair', () {
    expect(
      JobLocation(latitude: 30.0444, longitude: 31.2357).formatCoordinates(),
      '30.0444, 31.2357',
    );
  });

  group('Employee RouteTimeline per-job coordinates', () {
    testWidgets('Active job card renders real coordinates, not static labels',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      await tester.pumpWidget(_buildApp(_MockJobs(apiClient, initialJobs: [
        Job(
          id: 'job-coords-001',
          ownerId: 'owner-1',
          employeeId: 'emp-1',
          userId: 'cust-1',
          serviceId: 'service-1',
          status: 'active',
          location: JobLocation(latitude: 30.0444, longitude: 31.2357),
          destination: JobLocation(latitude: 30.05, longitude: 31.24),
          paymentMethod: 'cod',
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('30.0444, 31.2357'), findsOneWidget);
      expect(find.text('30.0500, 31.2400'), findsOneWidget);
      // Old static per-job strings must be gone.
      expect(find.text('Destination Coordinates'), findsNothing);
      expect(find.text('Client Address Confirmed'), findsNothing);
      // Static section titles stay.
      expect(find.text('Pickup Location'), findsOneWidget);
      expect(find.text('Delivery Destination'), findsOneWidget);
    });

    testWidgets('Offer card renders real coordinates too',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      await tester.pumpWidget(_buildApp(_MockJobs(apiClient, initialJobs: [
        Job(
          id: 'job-offer-002',
          ownerId: 'owner-1',
          userId: 'cust-2',
          serviceId: 'service-2',
          status: 'pending_dispatch',
          location: JobLocation(latitude: 29.9792, longitude: 31.1342),
          destination: JobLocation(latitude: 30.0444, longitude: 31.2357),
          paymentMethod: 'cod',
          currentOfferedEmployeeId: 'emp-1',
          offerExpiresAt: DateTime.now().add(const Duration(minutes: 4)),
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('29.9792, 31.1342'), findsOneWidget);
      expect(find.text('30.0444, 31.2357'), findsOneWidget);
      expect(find.text('Destination Coordinates'), findsNothing);
      expect(find.text('Client Address Confirmed'), findsNothing);
    });

    testWidgets('Null destination renders not-set fallback without throwing',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      await tester.pumpWidget(_buildApp(_MockJobs(apiClient, initialJobs: [
        Job(
          id: 'job-nodest-003',
          ownerId: 'owner-1',
          employeeId: 'emp-1',
          userId: 'cust-3',
          serviceId: 'service-3',
          status: 'active',
          location: JobLocation(latitude: 30.0444, longitude: 31.2357),
          destination: null,
          paymentMethod: 'cod',
        ),
      ])));
      await tester.pumpAndSettle();

      expect(find.text('30.0444, 31.2357'), findsOneWidget);
      expect(find.text('Destination not set yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
