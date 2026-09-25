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
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/customer_jobs_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/widgets/secondary_button.dart';

class _MockAuth extends AuthProvider {
  _MockAuth(super.apiClient);
  @override
  UserProfile? get user => UserProfile(
        id: 'u-1',
        email: 'test@example.com',
        username: 'TestUser',
        role: 'employee',
      );
  @override
  String? get token => 'test-token';
  @override
  Future<void> fetchUserProfile() async {}
}

class _MockEmployeeJobs extends EmployeeJobsProvider {
  final List<Job> initialJobs;
  bool requestCancellationCalled = false;
  String? lastRequestJobId;
  String? lastRequestReason;
  int fetchAssignedJobsCalls = 0;

  _MockEmployeeJobs(super.apiClient, {this.initialJobs = const []});

  @override
  List<Job> get jobs => List.unmodifiable(initialJobs);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {
    fetchAssignedJobsCalls++;
  }

  @override
  Future<Map<String, dynamic>> requestCancellation({
    required String jobId,
    required String reason,
    required String employeeToken,
  }) async {
    requestCancellationCalled = true;
    lastRequestJobId = jobId;
    lastRequestReason = reason;
    return {
      'message': 'cancellation request submitted for owner approval',
      'cancellation_request_status': 'pending'
    };
  }
}

class _MockMarketplace extends MarketplaceProvider {
  List<Job> mockCustomerJobs = [];
  bool cancelJobCalled = false;
  String? lastCancelledJobId;
  String? lastCancelledReason;
  int fetchCustomerJobsCalls = 0;

  _MockMarketplace(super.apiClient);

  @override
  List<Job> get customerJobs => mockCustomerJobs;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async {
    fetchCustomerJobsCalls++;
    return mockCustomerJobs;
  }

  @override
  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String userToken,
  }) async {
    cancelJobCalled = true;
    lastCancelledJobId = jobId;
    lastCancelledReason = reason;
    return {'message': 'job cancelled successfully', 'status': 'cancelled'};
  }
}

const _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _employeeApp(_MockEmployeeJobs jobsProvider) {
  final apiClient = ApiClient();
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: _delegates,
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

Widget _customerApp(_MockMarketplace marketplace) {
  final apiClient = ApiClient();
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _MockAuth(apiClient)),
        ChangeNotifierProvider<MarketplaceProvider>.value(value: marketplace),
        ChangeNotifierProvider<NotificationsProvider>(
            create: (_) => NotificationsProvider(apiClient)),
      ],
      child: const CustomerJobsScreen(),
    ),
  );
}

Job _job(String id, String status,
        {String paymentMethod = 'cod', String? cancellationRequestStatus}) =>
    Job(
      id: id,
      ownerId: 'owner-1',
      employeeId: 'emp-1',
      userId: 'cust-1',
      serviceId: 'service-1',
      status: status,
      location: JobLocation(latitude: 30.0444, longitude: 31.2357),
      destination: JobLocation(latitude: 30.05, longitude: 31.24),
      paymentMethod: paymentMethod,
      cancellationRequestStatus: cancellationRequestStatus,
    );

Future<void> _confirmDialogWithReason(
    WidgetTester tester, String reason) async {
  expect(find.byKey(const Key('cancel_reason_input')), findsOneWidget);
  await tester.enterText(find.byKey(const Key('cancel_reason_input')), reason);
  await tester.pump();
  await tester.tap(find.byKey(const Key('confirm_cancel_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('B1: employee job-card cancellation request (ADR-0027)', () {
    testWidgets('Request button visible for active/pending, absent when done',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final jobs = _MockEmployeeJobs(apiClient, initialJobs: [
        _job('job-emp-active', 'active'),
        _job('job-emp-pending', 'pending'),
      ]);
      await tester.pumpWidget(_employeeApp(jobs));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('employee_cancel_job_button_job-emp-active')),
          findsOneWidget);
      expect(
          find.byKey(const Key('employee_cancel_job_button_job-emp-pending')),
          findsOneWidget);
      // Eligible buttons are enabled, not disabled.
      final btn = tester.widget<SecondaryButton>(
          find.byKey(const Key('employee_cancel_job_button_job-emp-active')));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Completed/cancelled jobs render no request button',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final jobs = _MockEmployeeJobs(apiClient, initialJobs: [
        _job('job-emp-done', 'completed'),
        _job('job-emp-cx', 'cancelled'),
      ]);
      await tester.pumpWidget(_employeeApp(jobs));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('employee_cancel_job_button_job-emp-done')),
          findsNothing);
      expect(find.byKey(const Key('employee_cancel_job_button_job-emp-cx')),
          findsNothing);
    });

    testWidgets('Confirming dialog sends a request, not an immediate cancel',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final jobs = _MockEmployeeJobs(apiClient, initialJobs: [
        _job('job-emp-active', 'active'),
      ]);
      await tester.pumpWidget(_employeeApp(jobs));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('employee_cancel_job_button_job-emp-active'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      // Request-flow copy (not the immediate-cancel copy).
      expect(find.text('Request Cancellation'), findsWidgets);
      await _confirmDialogWithReason(tester, 'Vehicle broke down');

      expect(jobs.requestCancellationCalled, isTrue);
      expect(jobs.lastRequestJobId, 'job-emp-active');
      expect(jobs.lastRequestReason, 'Vehicle broke down');
      expect(jobs.fetchAssignedJobsCalls, greaterThan(0));
      expect(find.text('Cancellation request sent to the business owner.'),
          findsOneWidget);
    });

    testWidgets('Pending request hides the button and shows pending state',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final jobs = _MockEmployeeJobs(apiClient, initialJobs: [
        _job('job-emp-pending-req', 'active',
            cancellationRequestStatus: 'pending'),
      ]);
      await tester.pumpWidget(_employeeApp(jobs));
      await tester.pumpAndSettle();

      expect(
          find.byKey(
              const Key('employee_cancel_job_button_job-emp-pending-req')),
          findsNothing);
      expect(
          find.byKey(
              const Key('employee_cancel_request_pending_job-emp-pending-req')),
          findsOneWidget);
    });

    testWidgets('Rejected request shows the outcome and re-offers the button',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final jobs = _MockEmployeeJobs(apiClient, initialJobs: [
        _job('job-emp-rejected', 'active',
            cancellationRequestStatus: 'rejected'),
      ]);
      await tester.pumpWidget(_employeeApp(jobs));
      await tester.pumpAndSettle();

      expect(
          find.byKey(
              const Key('employee_cancel_request_rejected_job-emp-rejected')),
          findsOneWidget);
      expect(
          find.byKey(const Key('employee_cancel_job_button_job-emp-rejected')),
          findsOneWidget);
    });
  });

  group('B2: customer list-card cancel button', () {
    testWidgets('Cancel visible only for pending/pending_dispatch',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final marketplace = _MockMarketplace(apiClient)
        ..mockCustomerJobs = [
          _job('job-cust-pending', 'pending'),
          _job('job-cust-dispatch', 'pending_dispatch'),
          _job('job-cust-active', 'active'),
          _job('job-cust-done', 'completed'),
        ];
      await tester.pumpWidget(_customerApp(marketplace));
      // C9: fixed pumps — the pending_dispatch card's pulse dot loops
      // forever, so settle would time out here.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
          find.byKey(const Key('customer_cancel_job_button_job-cust-pending')),
          findsOneWidget);
      expect(
          find.byKey(const Key('customer_cancel_job_button_job-cust-dispatch')),
          findsOneWidget);
      expect(
          find.byKey(const Key('customer_cancel_job_button_job-cust-active')),
          findsNothing);
      expect(find.byKey(const Key('customer_cancel_job_button_job-cust-done')),
          findsNothing);
      final btn = tester.widget<SecondaryButton>(
          find.byKey(const Key('customer_cancel_job_button_job-cust-pending')));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Tapping cancel opens dialog, not the detail screen',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final marketplace = _MockMarketplace(apiClient)
        ..mockCustomerJobs = [_job('job-cust-pending', 'pending')];
      await tester.pumpWidget(_customerApp(marketplace));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('customer_cancel_job_button_job-cust-pending'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cancel_reason_input')), findsOneWidget);
      // Explicit negative: the inner Cancel button must win the gesture
      // arena — the card's JobStatusScreen navigation must NOT also fire.
      // (Mirrors the find.byType(JobStatusScreen) convention in
      // customer_jobs_screen_test.dart's positive navigation test.)
      expect(find.byType(JobStatusScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Confirming dialog cancels and reloads customer jobs',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final marketplace = _MockMarketplace(apiClient)
        ..mockCustomerJobs = [_job('job-cust-pending', 'pending')];
      await tester.pumpWidget(_customerApp(marketplace));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('customer_cancel_job_button_job-cust-pending'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      await _confirmDialogWithReason(tester, 'Changed my mind');

      expect(marketplace.cancelJobCalled, isTrue);
      expect(marketplace.lastCancelledJobId, 'job-cust-pending');
      expect(marketplace.lastCancelledReason, 'Changed my mind');
      expect(marketplace.fetchCustomerJobsCalls, greaterThan(0));
      expect(find.text('Job cancelled successfully.'), findsOneWidget);
    });
  });
}
