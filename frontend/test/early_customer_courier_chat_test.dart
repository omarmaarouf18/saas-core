import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/chat_screen.dart';
import 'package:frontend/screens/employee_jobs_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';

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
  final List<Job> initialJobs;

  MockEmployeeJobsProviderForTest(super.apiClient,
      {this.initialJobs = const []}) {
    _testJobs = List.from(initialJobs);
  }

  late List<Job> _testJobs;

  @override
  List<Job> get jobs => List.unmodifiable(_testJobs);

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {}
}

Widget createCustomerWidget({required Job job}) {
  final apiClient = ApiClient();
  final auth = MockAuthProviderForTest(
    apiClient,
    mockUser: UserProfile(
      id: 'cust-1',
      email: 'customer@example.com',
      role: 'user',
      username: 'Customer One',
    ),
  );
  final marketplaceProvider = MarketplaceProvider(apiClient);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<MarketplaceProvider>.value(
          value: marketplaceProvider),
      ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient)),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: JobStatusScreen(job: job, enablePolling: false),
    ),
  );
}

Widget createCourierWidget({required List<Job> jobs}) {
  final apiClient = ApiClient();
  final auth = MockAuthProviderForTest(
    apiClient,
    mockUser: UserProfile(
      id: 'emp-1',
      email: 'courier@example.com',
      role: 'employee',
      username: 'Courier Fast',
    ),
  );
  final jobsProvider =
      MockEmployeeJobsProviderForTest(apiClient, initialJobs: jobs);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<EmployeeJobsProvider>.value(value: jobsProvider),
      ChangeNotifierProvider<ChatProvider>(
          create: (_) => ChatProvider(apiClient)),
      ChangeNotifierProvider<EmployeeLocationProvider>(
          create: (_) => EmployeeLocationProvider(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => NotificationsProvider(apiClient)),
    ],
    child: const MaterialApp(
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
  final now = DateTime.now();

  group('Part B: Early Customer-Courier Chat Widget Tests', () {
    testWidgets(
        'Customer: JobStatusScreen renders early offered courier card & chat button when courier is offered',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final jobWithOffer = Job(
        id: 'job-partb-customer-1',
        ownerId: 'tenant-1',
        userId: 'cust-1',
        serviceId: 'svc-1',
        status: 'pending_dispatch',
        currentOfferedEmployeeId: 'emp-offered-42',
        offerExpiresAt: now.add(const Duration(seconds: 45)),
        location: JobLocation(latitude: 30.0444, longitude: 31.2357),
        paymentMethod: 'wallet',
      );

      await tester.pumpWidget(createCustomerWidget(job: jobWithOffer));
      await tester.pumpAndSettle();

      // Verify offered courier card is displayed
      expect(find.byKey(const Key('offered_courier_card')), findsOneWidget);
      expect(find.text('Courier found, reviewing your request...'),
          findsOneWidget);

      // Verify early chat button is present
      final chatBtn = find.byKey(const Key('early_chat_button'));
      expect(chatBtn, findsOneWidget);

      await tester.ensureVisible(chatBtn);
      await tester.tap(chatBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets(
        'Customer: JobStatusScreen does NOT render offered courier card when still searching (no offered courier)',
        (WidgetTester tester) async {
      final jobSearching = Job(
        id: 'job-partb-customer-searching',
        ownerId: 'tenant-1',
        userId: 'cust-1',
        serviceId: 'svc-1',
        status: 'pending_dispatch',
        currentOfferedEmployeeId: null,
        location: JobLocation(latitude: 30.0444, longitude: 31.2357),
        paymentMethod: 'wallet',
      );

      await tester.pumpWidget(createCustomerWidget(job: jobSearching));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offered_courier_card')), findsNothing);
      expect(find.byKey(const Key('early_chat_button')), findsNothing);
    });

    testWidgets(
        'Courier: EmployeeJobsScreen renders Chat with Customer button on incoming offer card',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final incomingOffer = Job(
        id: 'job-partb-courier-1',
        ownerId: 'tenant-1',
        userId: 'cust-1',
        serviceId: 'svc-1',
        status: 'pending_dispatch',
        currentOfferedEmployeeId: 'emp-1',
        offerExpiresAt: now.add(const Duration(seconds: 50)),
        location: JobLocation(latitude: 30.0444, longitude: 31.2357),
        paymentMethod: 'wallet',
      );

      await tester.pumpWidget(createCourierWidget(jobs: [incomingOffer]));
      await tester.pumpAndSettle();

      // Verify "Chat with Customer" button is present
      final chatBtn = find.byKey(Key('chat_customer_btn_${incomingOffer.id}'));
      expect(chatBtn, findsOneWidget);
      expect(find.text('Chat with Customer'), findsOneWidget);

      // Verify Accept and Decline are also present
      expect(find.byKey(Key('accept_offer_btn_${incomingOffer.id}')),
          findsOneWidget);
      expect(find.byKey(Key('decline_offer_btn_${incomingOffer.id}')),
          findsOneWidget);

      await tester.ensureVisible(chatBtn);
      await tester.tap(chatBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });
}
