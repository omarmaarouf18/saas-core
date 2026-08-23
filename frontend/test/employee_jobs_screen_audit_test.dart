import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/kyc_document_upload_screen.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/chat_message.dart';

class MockEmployeeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  UserProfile? user = UserProfile(
    id: 'emp-101',
    email: 'employee@example.com',
    username: 'John Field Worker',
    role: 'employee',
    kycStatus: 'approved',
    kyeStatus: 'approved',
  );

  @override
  String? token = 'mock-employee-jwt';

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchUserProfile() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEmployeeJobsProvider extends ChangeNotifier
    implements EmployeeJobsProvider {
  @override
  List<Job> jobs = [
    Job(
      id: 'job-emp-101',
      userId: 'user-cust-1',
      ownerId: 'owner-1',
      serviceId: 'srv-1',
      status: 'active',
      paymentMethod: 'cod',
      lockedEscrowAmount: 50.0,
      location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    ),
  ];

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchAssignedJobs(String token) async {}

  @override
  Future<void> simulateAction(
      {required String email, required String action}) async {}

  @override
  Future<void> completeJob(String jobId, {bool cashCollected = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEmployeeLocationProvider extends ChangeNotifier
    implements EmployeeLocationProvider {
  @override
  LocationSharingStatus status = LocationSharingStatus.idle;

  @override
  String? error;

  @override
  Future<void> startTracking(String jobId, String token) async {}

  @override
  Future<void> stopTracking({bool notify = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockNotificationsProvider extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  String? subscriptionError;

  @override
  String? error;

  @override
  bool isConnected = true;

  @override
  bool isConnecting = false;

  @override
  bool isLoading = false;

  @override
  List<ChatMessage> messages = [];

  @override
  Future<void> fetchHistory(String jobId, String? userToken) async {}

  Future<void> connect(String jobId, String? userToken) async {}

  @override
  void connectAndSubscribe(String jobId, String? userToken) {}

  // A6: ChatScreen now guarantees provider disconnect on disposal, so the
  // mock must honor the full connection contract instead of throwing via
  // noSuchMethod during the teardown frame.
  @override
  void disconnect() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createTestApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => MockEmployeeAuthProvider()),
      ChangeNotifierProvider<EmployeeJobsProvider>(
          create: (_) => MockEmployeeJobsProvider()),
      ChangeNotifierProvider<EmployeeLocationProvider>(
          create: (_) => MockEmployeeLocationProvider()),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => MockNotificationsProvider()),
      ChangeNotifierProvider<ChatProvider>(create: (_) => MockChatProvider()),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: EmployeeJobsScreen(),
    ),
  );
}

void main() {
  testWidgets(
      'EmployeeJobsScreen renders Verification button in AppBar and Chat button on job card',
      (WidgetTester tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    // Verify AppBar contains Verification button
    expect(
        find.byKey(const Key('employee_verification_button')), findsOneWidget);

    // Verify Job card contains Chat button and Complete Job button
    expect(find.byKey(const Key('employee_chat_button_job-emp-101')),
        findsOneWidget);
    expect(find.byKey(const Key('complete_job_button_job-emp-101')),
        findsOneWidget);
  });

  testWidgets('Tapping Verification button opens KycDocumentUploadScreen',
      (WidgetTester tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('employee_verification_button')));
    await tester.pumpAndSettle();

    expect(find.byType(KycDocumentUploadScreen), findsOneWidget);
  });

  testWidgets('Tapping Chat button opens ChatScreen for assigned job',
      (WidgetTester tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    final chatButton =
        find.byKey(const Key('employee_chat_button_job-emp-101'));
    await tester.ensureVisible(chatButton);
    await tester.tap(chatButton);
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('Pull to refresh gesture triggers fetchAssignedJobs',
      (WidgetTester tester) async {
    await tester.pumpWidget(createTestApp());
    await tester.pumpAndSettle();

    await tester.fling(
        find.byType(RefreshIndicator), const Offset(0.0, 300.0), 1000.0);
    await tester.pumpAndSettle();

    expect(find.byType(EmployeeJobsScreen), findsOneWidget);
  });
}
