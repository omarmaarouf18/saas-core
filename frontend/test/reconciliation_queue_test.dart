import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/screens/owner_reconciliation_queue_screen.dart';

class MockReconciliationProvider extends ReconciliationProvider {
  final List<ReconciliationJob> initialJobs;
  bool mockFetchError;
  final bool mockResolveConflict;
  int fetchQueueCallCount = 0;
  bool get fetchQueueCalled => fetchQueueCallCount > 0;
  bool resolveJobCalled = false;
  String? lastResolvedJobId;
  String? lastResolvedDecision;
  List<ReconciliationJob>? nextJobsOnFetch;

  MockReconciliationProvider(
    super.apiClient, {
    this.initialJobs = const [],
    this.mockFetchError = false,
    this.mockResolveConflict = false,
  }) {
    _testQueue = List.from(initialJobs);
    if (mockFetchError) {
      _testError = 'Access denied: owner authorization required';
    }
  }

  late List<ReconciliationJob> _testQueue;
  String? _testError;

  @override
  List<ReconciliationJob> get queue => List.unmodifiable(_testQueue);

  @override
  String? get error => _testError;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchQueue() async {
    fetchQueueCallCount++;
    if (mockFetchError) {
      _testError = 'Access denied: owner authorization required';
    } else {
      _testError = null;
      if (nextJobsOnFetch != null) {
        _testQueue = List.from(nextJobsOnFetch!);
      }
    }
    notifyListeners();
  }

  void setNextFetchResult(
      {List<ReconciliationJob>? jobs, bool hasError = false}) {
    mockFetchError = hasError;
    if (jobs != null) {
      nextJobsOnFetch = jobs;
    }
  }

  @override
  Future<bool> resolveJob({
    required String jobId,
    required String decision,
  }) async {
    resolveJobCalled = true;
    lastResolvedJobId = jobId;
    lastResolvedDecision = decision;

    if (mockResolveConflict) {
      _testError = 'Job already resolved';
      notifyListeners();
      return false;
    }

    _testQueue.removeWhere((j) => j.id == jobId);
    notifyListeners();
    return true;
  }

  @override
  void setError(String? err) {
    _testError = err;
    notifyListeners();
  }

  @override
  void clearError() {
    _testError = null;
    notifyListeners();
  }
}

Widget buildReconciliationApp(MockReconciliationProvider mockProvider) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<ReconciliationProvider>.value(
      value: mockProvider,
      child: const OwnerReconciliationQueueScreen(),
    ),
  );
}

void main() {
  final testJob = ReconciliationJob(
    id: 'job-test-101',
    ownerId: 'owner-1',
    serviceId: 'service-shipping-1',
    userId: 'customer-1',
    employeeId: 'employee-1',
    status: 'escrow_reconciliation_required',
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'escrow',
    lockedEscrowAmount: 50.0,
    reconciliationNote: 'actual 2.00 km vs booked 10.00 km',
    escrowFailureReason: 'under_distance_mismatch',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets('(a) Queue loads and renders job cards with correct fields',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [testJob],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    // Verify job ID, human-readable failure reason, note, and locked escrow amount
    expect(find.text('Order #job-test-101'), findsOneWidget);
    expect(find.text('Distance mismatch — under 70% of booked distance'),
        findsOneWidget);
    expect(find.text('actual 2.00 km vs booked 10.00 km'), findsOneWidget);
    expect(find.text('50.00 Credits'), findsOneWidget);
    expect(find.text('RECONCILIATION REQUIRED'), findsOneWidget);
    expect(find.text('Release to Employee'), findsOneWidget);
    expect(find.text('Refund to Customer'), findsOneWidget);
  });

  testWidgets('(b) Empty state renders when queue is empty',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    expect(find.text('No jobs pending reconciliation'), findsOneWidget);
    expect(
        find.text(
            'All escrow transactions are healthy. No flagged jobs require manual review.'),
        findsOneWidget);
  });

  testWidgets('(c) Confirmation dialog appears before resolve action fires',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [testJob],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    // Tap Release to Employee
    await tester.tap(find.text('Release to Employee'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog renders with title and text
    expect(find.text('Confirm Release to Employee'), findsNWidgets(2));
    expect(
        find.textContaining(
            'This will transfer 50.00 Credits back to the employee/tenant.'),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel out of dialog
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Verify resolveJob was NOT called
    expect(mockProvider.resolveJobCalled, isFalse);
  });

  testWidgets('(d) Successful resolve removes job from visible list',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [testJob],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    // Tap Release to Employee
    await tester.tap(find.text('Release to Employee'));
    await tester.pumpAndSettle();

    // Confirm in dialog
    await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm Release to Employee'));
    await tester.pumpAndSettle();

    // Verify resolveJob was called and job removed
    expect(mockProvider.resolveJobCalled, isTrue);
    expect(mockProvider.lastResolvedJobId, 'job-test-101');
    expect(mockProvider.lastResolvedDecision, 'release_to_employee');

    // Job card should be gone and empty state rendered
    expect(find.text('Order #job-test-101'), findsNothing);
    expect(find.text('No jobs pending reconciliation'), findsOneWidget);
    expect(find.text('Escrow resolved: funds released to employee/tenant'),
        findsOneWidget);
  });

  testWidgets('(e) 409 already resolved response shows specific error message',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [testJob],
      mockResolveConflict: true,
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    // Tap Refund to Customer
    await tester.tap(find.text('Refund to Customer'));
    await tester.pumpAndSettle();

    // Confirm in dialog
    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Confirm Refund to Customer'));
    await tester.pumpAndSettle();

    // Verify 409 conflict message appears in SnackBar
    expect(find.text('Job already resolved'), findsOneWidget);
  });

  testWidgets(
      '(f) Empty state Refresh Queue action button actually invokes fetchQueue and transitions UI to loaded state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    expect(find.text('No jobs pending reconciliation'), findsOneWidget);
    expect(mockProvider.fetchQueueCallCount, 1); // initial initState load

    // Configure next fetch to return a job
    mockProvider.setNextFetchResult(jobs: [testJob]);

    // Tap 'Refresh Queue' action button inside ThemedEmptyState
    final refreshBtn = find.text('Refresh Queue');
    expect(refreshBtn, findsOneWidget);
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    // Verify fetchQueue was called again
    expect(mockProvider.fetchQueueCallCount, 2);

    // Verify UI transitioned from empty state to populated job card
    expect(find.text('No jobs pending reconciliation'), findsNothing);
    expect(find.text('Order #job-test-101'), findsOneWidget);
  });

  testWidgets('(g) Pull-to-refresh on empty queue invokes fetchQueue',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    expect(mockProvider.fetchQueueCallCount, 1);

    // Perform pull-down gesture on the RefreshIndicator
    await tester.fling(
        find.byType(SingleChildScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(mockProvider.fetchQueueCallCount, 2);
  });

  testWidgets('(h) Pull-to-refresh on populated queue invokes fetchQueue',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [testJob],
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    expect(mockProvider.fetchQueueCallCount, 1);
    expect(find.text('Order #job-test-101'), findsOneWidget);

    // Perform pull-down gesture on the ListView
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(mockProvider.fetchQueueCallCount, 2);
  });

  testWidgets(
      '(i) Error state Retry button invokes fetchQueue and transitions UI to loaded state',
      (WidgetTester tester) async {
    final apiClient = ApiClient();
    final mockProvider = MockReconciliationProvider(
      apiClient,
      initialJobs: [],
      mockFetchError: true,
    );

    await tester.pumpWidget(buildReconciliationApp(mockProvider));
    await tester.pumpAndSettle();

    // Verify initial load resulted in error UI
    expect(find.text('Access denied: owner authorization required'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(mockProvider.fetchQueueCallCount, 1);

    // Set mock to succeed on retry and provide job
    mockProvider.setNextFetchResult(jobs: [testJob], hasError: false);

    // Tap Retry
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // Verify fetchQueue was called again
    expect(mockProvider.fetchQueueCallCount, 2);

    // Verify UI transitioned from error state to loaded job card
    expect(
        find.text('Access denied: owner authorization required'), findsNothing);
    expect(find.text('Order #job-test-101'), findsOneWidget);
  });
}
