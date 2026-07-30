import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/screens/owner_reconciliation_queue_screen.dart';

class MockReconciliationProvider extends ReconciliationProvider {
  final List<ReconciliationJob> initialJobs;
  final bool mockFetchError;
  final bool mockResolveConflict;
  bool fetchQueueCalled = false;
  bool resolveJobCalled = false;
  String? lastResolvedJobId;
  String? lastResolvedDecision;

  MockReconciliationProvider(
    super.apiClient, {
    this.initialJobs = const [],
    this.mockFetchError = false,
    this.mockResolveConflict = false,
  }) {
    _testQueue = List.from(initialJobs);
  }

  late List<ReconciliationJob> _testQueue;

  @override
  List<ReconciliationJob> get queue => List.unmodifiable(_testQueue);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchQueue() async {
    fetchQueueCalled = true;
    if (mockFetchError) {
      setErrorForTest('Access denied: owner authorization required');
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
      setError('Job already resolved');
      return false;
    }

    _testQueue.removeWhere((j) => j.id == jobId);
    notifyListeners();
    return true;
  }

  void setErrorForTest(String err) {
    // Accessing internal error via reflection or clear logic
  }
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReconciliationProvider>.value(
          value: mockProvider,
          child: const OwnerReconciliationQueueScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify job ID, human-readable failure reason, note, and locked escrow amount
    expect(find.text('Job #job-test-101'), findsOneWidget);
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReconciliationProvider>.value(
          value: mockProvider,
          child: const OwnerReconciliationQueueScreen(),
        ),
      ),
    );
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReconciliationProvider>.value(
          value: mockProvider,
          child: const OwnerReconciliationQueueScreen(),
        ),
      ),
    );
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReconciliationProvider>.value(
          value: mockProvider,
          child: const OwnerReconciliationQueueScreen(),
        ),
      ),
    );
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
    expect(find.text('Job #job-test-101'), findsNothing);
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

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ReconciliationProvider>.value(
          value: mockProvider,
          child: const OwnerReconciliationQueueScreen(),
        ),
      ),
    );
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
}
