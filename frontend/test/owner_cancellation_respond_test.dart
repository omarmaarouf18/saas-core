import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/screens/home_screen.dart';
import 'package:frontend/widgets/confirm_action_dialog.dart';
import 'package:frontend/widgets/primary_button.dart';
import 'package:frontend/widgets/secondary_button.dart';

class _MockOwnerAuth extends AuthProvider {
  _MockOwnerAuth(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'owner-test-1',
        email: 'owner@example.com',
        username: 'test_owner',
        role: 'owner',
        kycStatus: 'approved',
      );

  @override
  String? get token => 'mock-owner-token';

  @override
  Future<bool> fetchUserProfile() async => true;
}

class _MockOwnerRespond extends OwnerProvider {
  final List<Job> mockJobs;
  int respondCalls = 0;
  String? lastJobId;
  String? lastDecision;
  bool throwExpired = false;

  _MockOwnerRespond(super.apiClient, {this.mockJobs = const []});

  @override
  double get walletBalance => 500.0;

  @override
  String get subscriptionTier => 'paid';

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  List<Job> get ownerJobs => mockJobs;

  @override
  Future<void> fetchDashboardData(String ownerToken) async {}

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {}

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async => [];

  @override
  Future<Map<String, dynamic>> respondCancellation({
    required String jobId,
    required String decision,
    required String ownerToken,
  }) async {
    respondCalls++;
    lastJobId = jobId;
    lastDecision = decision;
    if (throwExpired) {
      throw ApiClientException(
        'this cancellation request already expired and was auto-resolved',
        statusCode: 409,
      );
    }
    return {'message': 'cancellation request resolved', 'job_id': jobId};
  }
}

class _MockMarketplace extends MarketplaceProvider {
  _MockMarketplace(super.apiClient);

  @override
  List<Job> get customerJobs => [];

  @override
  Future<List<Job>> fetchCustomerJobs([String? token]) async => [];
}

class _MockNotifications extends NotificationsProvider {
  _MockNotifications(super.apiClient);

  @override
  int get unreadCount => 0;

  void connect(String token) {}

  void disconnect() {}
}

Widget _ownerApp(OwnerProvider ownerProvider) {
  final apiClient = ApiClient();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(
          create: (_) => _MockOwnerAuth(apiClient)),
      ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
      ChangeNotifierProvider<MarketplaceProvider>(
          create: (_) => _MockMarketplace(apiClient)),
      ChangeNotifierProvider<NotificationsProvider>(
          create: (_) => _MockNotifications(apiClient)),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: quickDeliveryTheme,
      home: const HomeScreen(),
    ),
  );
}

Job _ownerJob(String id,
    {String status = 'active', String? requestStatus, String? reason}) {
  return Job(
    id: id,
    ownerId: 'owner-test-1',
    employeeId: 'emp-1',
    userId: 'cust-1',
    serviceId: 'service-1',
    status: status,
    location: JobLocation(latitude: 30.0444, longitude: 31.2357),
    paymentMethod: 'cod',
    cancellationRequestStatus: requestStatus,
    cancellationRequestReason: reason,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Owner cancellation-request response (ADR-0027)', () {
    testWidgets('Pending block renders with reason and both buttons',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apiClient = ApiClient();
      final ownerProvider = _MockOwnerRespond(apiClient, mockJobs: [
        _ownerJob('job-req-1',
            requestStatus: 'pending', reason: 'Family emergency'),
        _ownerJob('job-plain-1'),
      ]);
      await tester.pumpWidget(_ownerApp(ownerProvider));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('owner_cancel_request_job-req-1')),
          findsOneWidget);
      expect(find.byKey(const Key('owner_cancel_request_job-plain-1')),
          findsNothing);
      expect(find.textContaining('Family emergency'), findsOneWidget);
      expect(find.byKey(const Key('approve_cancel_request_button_job-req-1')),
          findsOneWidget);
      expect(find.byKey(const Key('decline_cancel_request_button_job-req-1')),
          findsOneWidget);
    });

    testWidgets('Approve shows confirm dialog; cancel does not call respond',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apiClient = ApiClient();
      final ownerProvider = _MockOwnerRespond(apiClient, mockJobs: [
        _ownerJob('job-req-1',
            requestStatus: 'pending', reason: 'Family emergency'),
      ]);
      await tester.pumpWidget(_ownerApp(ownerProvider));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('approve_cancel_request_button_job-req-1'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      // Dialog opens with consequences explained
      expect(find.byType(ConfirmActionDialog), findsOneWidget);
      expect(find.text('Approve Cancellation?'), findsOneWidget);
      expect(find.textContaining('trigger a full refund'), findsOneWidget);

      // Cancel button inside dialog does not submit
      final cancelBtn = find.descendant(
        of: find.byType(ConfirmActionDialog),
        matching: find.byType(SecondaryButton),
      );
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmActionDialog), findsNothing);
      expect(ownerProvider.respondCalls, 0);
    });

    testWidgets(
        'Approve confirms dialog, calls respond with accept, shows specific success',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apiClient = ApiClient();
      final ownerProvider = _MockOwnerRespond(apiClient, mockJobs: [
        _ownerJob('job-req-1',
            requestStatus: 'pending', reason: 'Family emergency'),
      ]);
      await tester.pumpWidget(_ownerApp(ownerProvider));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('approve_cancel_request_button_job-req-1'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmActionDialog), findsOneWidget);
      final confirmBtn = find.descendant(
        of: find.byType(ConfirmActionDialog),
        matching: find.byType(PrimaryButton),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(ownerProvider.respondCalls, 1);
      expect(ownerProvider.lastJobId, 'job-req-1');
      expect(ownerProvider.lastDecision, 'accept');
      expect(
        find.text(
            'Cancellation request approved. Job cancelled and escrow refunded.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Decline confirms dialog, calls respond with decline, shows specific success',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apiClient = ApiClient();
      final ownerProvider = _MockOwnerRespond(apiClient, mockJobs: [
        _ownerJob('job-req-1',
            requestStatus: 'pending', reason: 'Family emergency'),
      ]);
      await tester.pumpWidget(_ownerApp(ownerProvider));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('decline_cancel_request_button_job-req-1'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmActionDialog), findsOneWidget);
      expect(find.text('Decline Cancellation Request?'), findsOneWidget);
      expect(find.textContaining('keep the job active with the courier'),
          findsOneWidget);

      final confirmBtn = find.descendant(
        of: find.byType(ConfirmActionDialog),
        matching: find.byType(PrimaryButton),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(ownerProvider.respondCalls, 1);
      expect(ownerProvider.lastDecision, 'decline');
      expect(
        find.text('Cancellation request declined. Courier remains assigned.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Late (already-expired) response surfaces the server message after confirm',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apiClient = ApiClient();
      final ownerProvider = _MockOwnerRespond(apiClient, mockJobs: [
        _ownerJob('job-req-1',
            requestStatus: 'pending', reason: 'Family emergency'),
      ])
        ..throwExpired = true;
      await tester.pumpWidget(_ownerApp(ownerProvider));
      await tester.pumpAndSettle();

      final btn =
          find.byKey(const Key('approve_cancel_request_button_job-req-1'));
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmActionDialog), findsOneWidget);
      final confirmBtn = find.descendant(
        of: find.byType(ConfirmActionDialog),
        matching: find.byType(PrimaryButton),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(ownerProvider.respondCalls, 1);
      // No silent failure: the expired explanation reaches the owner.
      expect(find.textContaining('already expired'), findsOneWidget);
    });
  });
}
