import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/features/owner/owner_controller.dart';
import 'package:frontend/features/owner/owner_nav.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/payout_request.dart';
import 'package:frontend/models/reconciliation_job.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/providers/reconciliation_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_launcher.dart';
import '../customer/customer_harness.dart' show BlankTileProvider;

export '../../helpers/fake_launcher.dart';

export '../customer/customer_harness.dart'
    show ar, en, bothLocales, fixedNow, usePhone, loadPlexFont;

/// Shared fakes and pump helpers for the FE-OWNER-1 page tests.

final DateTime ownerNow = DateTime(2026, 10, 19, 15, 30);

class FakeOwnerAuth extends ChangeNotifier implements AuthProvider {
  FakeOwnerAuth({String kycStatus = 'approved', String? rejectionReason})
      : user = UserProfile(
          id: 'owner-1',
          email: 'owner@example.com',
          username: 'Nile Express',
          role: 'owner',
          kycStatus: kycStatus,
          rejectionReason: rejectionReason,
        );

  @override
  UserProfile? user;

  @override
  String? token = 'owner-jwt';

  @override
  bool isLoading = false;

  @override
  String? error;

  int profileCalls = 0;

  @override
  Future<void> fetchUserProfile() async {
    profileCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// OwnerProvider fake: the test sets what the next fetch returns; calls are
/// recorded. Gates hold a call open (loading states, double taps).
class FakeOwner extends ChangeNotifier implements OwnerProvider {
  @override
  List<Job> ownerJobs = [];

  @override
  List<dynamic> employees = [];

  Map<String, Map<String, dynamic>> jobJson = {};

  @override
  Map<String, dynamic>? ownerJobJson(String jobId) => jobJson[jobId];

  @override
  String? ownerJobsError;

  @override
  String? employeesError;

  @override
  bool isLoading = false;

  @override
  String? error;

  List<Job> nextJobs = [];
  Map<String, Map<String, dynamic>> nextJobJson = {};
  String? nextJobsError;
  List<dynamic> nextEmployees = [];
  String? nextEmployeesError;
  Completer<void>? jobsGate;

  int jobCalls = 0;
  int employeeCalls = 0;

  void seed({List<Job>? jobs, List<dynamic>? staff}) {
    if (jobs != null) nextJobs = ownerJobs = jobs;
    if (staff != null) nextEmployees = employees = staff;
  }

  @override
  Future<void> fetchOwnerJobs(String ownerToken) async {
    jobCalls++;
    if (jobsGate != null) await jobsGate!.future;
    if (nextJobsError != null) {
      ownerJobsError = error = nextJobsError;
    } else {
      ownerJobs = List.of(nextJobs);
      jobJson = Map.of(nextJobJson);
      ownerJobsError = error = null;
    }
    notifyListeners();
  }

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async {
    employeeCalls++;
    if (nextEmployeesError != null) {
      employeesError = error = nextEmployeesError;
      employees = [];
    } else {
      employees = List.of(nextEmployees);
      employeesError = error = null;
    }
    notifyListeners();
    return employees;
  }

  final List<Map<String, String>> respondCalls = [];
  Object? nextRespondError;
  Completer<void>? respondGate;

  /// What the job list looks like after a successful response.
  List<Job>? jobsAfterRespond;

  @override
  Future<Map<String, dynamic>> respondCancellation({
    required String jobId,
    required String decision,
    required String ownerToken,
  }) async {
    respondCalls.add({'jobId': jobId, 'decision': decision});
    if (respondGate != null) await respondGate!.future;
    if (nextRespondError != null) throw nextRespondError!;
    if (jobsAfterRespond != null) nextJobs = jobsAfterRespond!;
    await fetchOwnerJobs(ownerToken);
    return {'message': 'ok'};
  }

  final List<Map<String, String>> cancelCalls = [];
  Object? nextCancelError;

  @override
  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String ownerToken,
  }) async {
    cancelCalls.add({'jobId': jobId, 'reason': reason});
    if (nextCancelError != null) throw nextCancelError!;
    ownerJobs = [
      for (final j in ownerJobs)
        j.id == jobId ? copyJob(j, status: 'cancelled', reason: reason) : j
    ];
    notifyListeners();
    return {'status': 'cancelled'};
  }

  final List<Map<String, String>> registerCalls = [];
  Object? nextRegisterError;
  Completer<void>? registerGate;

  @override
  Future<Map<String, dynamic>> registerEmployee({
    required String email,
    required String username,
    required String password,
    required String ownerId,
  }) async {
    registerCalls.add({
      'email': email,
      'username': username,
      'password': password,
      'ownerId': ownerId,
    });
    if (registerGate != null) await registerGate!.future;
    if (nextRegisterError != null) throw nextRegisterError!;
    return {'user_id': 'emp-new', 'username': username};
  }

  final List<Map<String, Object>> toggleCalls = [];
  Object? nextToggleError;
  Completer<void>? toggleGate;

  @override
  Future<Map<String, dynamic>> toggleEmployee({
    required String employeeEmail,
    required String ownerEmail,
    required String ownerPassword,
    required bool setActive,
  }) async {
    toggleCalls.add({
      'employeeEmail': employeeEmail,
      'ownerEmail': ownerEmail,
      'ownerPassword': ownerPassword,
      'setActive': setActive,
    });
    if (toggleGate != null) await toggleGate!.future;
    if (nextToggleError != null) throw nextToggleError!;
    nextEmployees = [
      for (final e in nextEmployees)
        if (e is Map && e['email'] == employeeEmail)
          {...e, 'is_active': setActive}
        else
          e
    ];
    return {'message': 'updated'};
  }

  // FE-OWNER-2: audit log (activity log).
  @override
  List<dynamic> auditLogEntries = [];

  @override
  String? auditLogError;

  List<dynamic> nextAudit = [];
  String? nextAuditError;
  Completer<void>? auditGate;
  final List<Map<String, String>> auditCalls = [];

  @override
  Future<void> fetchAuditLog({
    required String tenantId,
    required String requesterToken,
  }) async {
    auditCalls.add({'tenantId': tenantId, 'token': requesterToken});
    if (auditGate != null) await auditGate!.future;
    if (nextAuditError != null) {
      auditLogError = error = nextAuditError;
    } else {
      auditLogEntries = List.of(nextAudit);
      auditLogError = error = null;
    }
    notifyListeners();
  }

  // FE-OWNER-2: wallet, subscription and ledger (fetchDashboardData).
  @override
  double walletBalance = 0;

  @override
  double escrowBalance = 0;

  @override
  double withdrawableBalance = 0;

  @override
  String subscriptionTier = 'free';

  @override
  List<dynamic> ledgerEntries = [];

  @override
  String? dashboardError;

  @override
  bool isDashboardHydrated = false;

  /// What the next fetchDashboardData loads (null keeps the values).
  ({double total, double escrow, double withdrawable, String tier})? nextWallet;
  List<dynamic> nextLedger = [];
  String? nextDashboardError;
  Completer<void>? dashboardGate;
  final List<String> dashboardCalls = [];

  @override
  Future<void> fetchDashboardData(String tenantId) async {
    dashboardCalls.add(tenantId);
    if (dashboardGate != null) await dashboardGate!.future;
    if (nextDashboardError != null) {
      dashboardError = error = nextDashboardError;
    } else {
      final w = nextWallet;
      if (w != null) {
        walletBalance = w.total;
        escrowBalance = w.escrow;
        withdrawableBalance = w.withdrawable;
        subscriptionTier = w.tier;
      }
      subscriptionExpiresAt = nextExpiresAt;
      ledgerEntries = List.of(nextLedger);
      isDashboardHydrated = true;
      dashboardError = error = null;
    }
    notifyListeners();
  }

  // FE-OWNER-2b: subscription expiry, withdrawals, and the money calls the
  // read-only pages must never make.
  @override
  DateTime? subscriptionExpiresAt;

  /// What the next successful fetchDashboardData sets as the expiry.
  DateTime? nextExpiresAt;

  @override
  List<PayoutRequest> payoutRequests = [];

  @override
  String? payoutRequestsError;

  List<PayoutRequest> nextPayouts = [];
  String? nextPayoutsError;
  int payoutCalls = 0;

  @override
  Future<List<PayoutRequest>> fetchPayoutRequests() async {
    payoutCalls++;
    if (nextPayoutsError != null) {
      payoutRequestsError = error = nextPayoutsError;
    } else {
      payoutRequests = List.of(nextPayouts);
      payoutRequestsError = error = null;
    }
    notifyListeners();
    return payoutRequests;
  }

  /// Calls that move money (must stay empty).
  final List<String> moneyCalls = [];

  @override
  Future<void> deposit(String token, double amount) async =>
      moneyCalls.add('deposit');

  @override
  Future<PayoutRequest> requestPayout({
    required double amount,
    required String payoutMethod,
    required String accountDetails,
  }) async {
    moneyCalls.add('requestPayout');
    throw UnimplementedError();
  }

  /// Plan change requests (tenant token, tier), like the server: `paid`
  /// becomes `pending_payment`, `free` applies at once.
  final List<String> subscriptionCalls = [];
  Object? nextSubscriptionError;
  Completer<void>? subscriptionGate;

  @override
  Future<Map<String, dynamic>> updateSubscription({
    required String tenantId,
    required String tier,
  }) async {
    subscriptionCalls.add('$tenantId:$tier');
    if (subscriptionGate != null) await subscriptionGate!.future;
    final e = nextSubscriptionError;
    if (e != null) {
      nextSubscriptionError = null;
      throw e;
    }
    subscriptionTier = tier == 'paid' ? 'pending_payment' : 'free';
    final w = nextWallet;
    if (w != null) {
      nextWallet = (
        total: w.total,
        escrow: w.escrow,
        withdrawable: w.withdrawable,
        tier: subscriptionTier
      );
    }
    if (tier == 'free') nextExpiresAt = null;
    notifyListeners();
    return tier == 'paid'
        ? {'status': 'pending_payment', 'message': 'manual activation'}
        : {'tier': 'free'};
  }

  @override
  Future<void> fetchPaymentAvailability() async =>
      moneyCalls.add('fetchPaymentAvailability');

  // FE-OWNER-2: services (service setup).
  @override
  List<dynamic> services = [];

  @override
  String? servicesError;

  List<dynamic> nextServices = [];
  String? nextServicesError;
  Completer<void>? servicesGate;
  int serviceCalls = 0;

  @override
  Future<void> fetchServices() async {
    serviceCalls++;
    if (servicesGate != null) await servicesGate!.future;
    if (nextServicesError != null) {
      servicesError = error = nextServicesError;
    } else {
      services = List.of(nextServices);
      servicesError = error = null;
    }
    notifyListeners();
  }

  final List<Map<String, dynamic>> createCalls = [];
  Object? nextCreateError;
  Map<String, dynamic> nextCreateResponse = {
    'message': 'service created',
    'service': {'id': 'svc-new'},
  };

  @override
  Future<Map<String, dynamic>> createService({
    required String name,
    required String category,
    required double tenantBasePrice,
    required double tenantPricePerKM,
    required double latitude,
    required double longitude,
    required String ownerId,
  }) async {
    createCalls.add({
      'name': name,
      'category': category,
      'tenant_base_price': tenantBasePrice,
      'tenant_price_per_km': tenantPricePerKM,
      'latitude': latitude,
      'longitude': longitude,
      'owner_id': ownerId,
    });
    if (nextCreateError != null) throw nextCreateError!;
    return nextCreateResponse;
  }

  final List<Map<String, dynamic>> updateCalls = [];
  Object? nextUpdateError;
  Completer<void>? updateGate;

  @override
  Future<Map<String, dynamic>> updateOwnerServiceConfig({
    required String serviceId,
    required String ownerId,
    String? name,
    String? category,
    double? tenantBasePrice,
    double? tenantPricePerKM,
    String? photoUrl,
    String? address,
    String? workingHours,
    double? coverageRadiusKm,
    double? latitude,
    double? longitude,
    String? scheduleMode,
    String? openTime,
    String? closeTime,
    List<Map<String, dynamic>>? perDaySchedule,
    String? timezone,
  }) async {
    final call = <String, dynamic>{
      'service_id': serviceId,
      'owner_id': ownerId,
      'name': name,
      'category': category,
      'tenant_base_price': tenantBasePrice,
      'tenant_price_per_km': tenantPricePerKM,
      'photo_url': photoUrl,
      'address': address,
      'working_hours': workingHours,
      'coverage_radius_km': coverageRadiusKm,
      'latitude': latitude,
      'longitude': longitude,
      'schedule_mode': scheduleMode,
      'open_time': openTime,
      'close_time': closeTime,
      'per_day_schedule': perDaySchedule,
      'timezone': timezone,
    }..removeWhere((_, v) => v == null);
    updateCalls.add(call);
    if (updateGate != null) await updateGate!.future;
    if (nextUpdateError != null) throw nextUpdateError!;
    return {'message': 'service updated'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRatings extends ChangeNotifier implements MarketplaceProvider {
  Map<String, dynamic> nextRatings = {'average_rating': 4.6, 'count': 23};
  Object? nextRatingsError;
  Completer<void>? ratingsGate;
  final List<String> ratingsCalls = [];

  @override
  Future<Map<String, dynamic>> fetchRatings(String userTokenOrId) async {
    ratingsCalls.add(userTokenOrId);
    if (ratingsGate != null) await ratingsGate!.future;
    if (nextRatingsError != null) throw nextRatingsError!;
    return nextRatings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRecon extends ChangeNotifier implements ReconciliationProvider {
  List<ReconciliationJob> _queue = [];

  @override
  List<ReconciliationJob> get queue => List.unmodifiable(_queue);

  @override
  bool isLoading = false;

  @override
  String? error;

  List<ReconciliationJob> nextQueue = [];
  String? nextQueueError;
  Completer<void>? queueGate;
  int queueCalls = 0;

  @override
  Future<void> fetchQueue() async {
    queueCalls++;
    isLoading = true;
    error = null;
    notifyListeners();
    if (queueGate != null) await queueGate!.future;
    isLoading = false;
    if (nextQueueError != null) {
      error = nextQueueError;
    } else {
      _queue = List.of(nextQueue);
    }
    notifyListeners();
  }

  final List<Map<String, String>> resolveCalls = [];
  String? nextResolveError;
  Completer<void>? resolveGate;

  @override
  Future<bool> resolveJob(
      {required String jobId, required String decision}) async {
    resolveCalls.add({'jobId': jobId, 'decision': decision});
    isLoading = true;
    error = null;
    notifyListeners();
    if (resolveGate != null) await resolveGate!.future;
    isLoading = false;
    if (nextResolveError != null) {
      error = nextResolveError;
      notifyListeners();
      return false;
    }
    _queue.removeWhere((j) => j.id == jobId);
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fleet map fake (FE-OWNER-2): tests set markers and connection state;
/// hydrations, subscriptions, name lookups and disconnects are recorded.
class FakeOwnerMap extends ChangeNotifier implements MapTrackingProvider {
  @override
  List<EmployeeMarkerData> markersList = [];

  @override
  bool isLoading = false;

  @override
  bool isConnected = true;

  @override
  String? error;

  @override
  String? subscriptionError;

  final List<String> hydrateCalls = [];
  final List<String> subscribeCalls = [];
  Map<String, String> names = const {};
  int disconnects = 0;

  /// What the next hydration loads.
  List<EmployeeMarkerData>? nextMarkers;
  String? nextError;

  @override
  Future<void> hydrateOwnerFleet(String ownerToken) async {
    hydrateCalls.add(ownerToken);
    if (nextError != null) {
      error = nextError;
    } else {
      error = null;
      if (nextMarkers != null) markersList = List.of(nextMarkers!);
    }
    notifyListeners();
  }

  @override
  void connectAndSubscribe(String channel, String token,
      {Object? customChannel}) {
    subscribeCalls.add(channel);
  }

  @override
  void setEmployeeNameLookup(Map<String, String> lookup) {
    names = Map.of(lookup);
    markersList = [
      for (final m in markersList)
        EmployeeMarkerData(
          employeeId: m.employeeId,
          employeeName: lookup[m.employeeId],
          jobId: m.jobId,
          latitude: m.latitude,
          longitude: m.longitude,
          updatedAt: m.updatedAt,
        ),
    ];
    notifyListeners();
  }

  @override
  void disconnect() {
    disconnects++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

EmployeeMarkerData courierAt(String id,
        {String? jobId,
        double lat = 30.05,
        double lon = 31.24,
        DateTime? updatedAt}) =>
    EmployeeMarkerData(
      employeeId: id,
      jobId: jobId,
      latitude: lat,
      longitude: lon,
      updatedAt: updatedAt ?? ownerNow.subtract(const Duration(minutes: 3)),
    );

class FakeOwnerNotifications extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTheme extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records hand-offs to screens that are not rebuilt (KYB upload, fleet
/// map, notifications, service setup, wallet, subscription, history).
/// New pages are still pushed for real.
class RecordingOwnerNav extends OwnerNav {
  final List<String> opened = [];

  @override
  Future<void> openNotifications(BuildContext context) async =>
      opened.add('notifications');

  @override
  Future<void> openKyb(BuildContext context) async => opened.add('kyb');

  /// The courier the last fleet map hand-off focused.
  String? fleetFocus;

  @override
  Future<void> openFleetMap(BuildContext context, {String? employeeId}) async {
    opened.add('fleet_map');
    fleetFocus = employeeId;
  }

  @override
  Future<void> openServiceSetup(BuildContext context) async =>
      opened.add('service_setup');

  @override
  Future<void> openWallet(BuildContext context) async => opened.add('wallet');

  @override
  Future<void> openSubscription(BuildContext context) async =>
      opened.add('subscription');

  @override
  Future<void> openHistory(BuildContext context) async => opened.add('history');

  @override
  Future<void> openSupport(BuildContext context) async => opened.add('support');
}

class OwnerTestDeps {
  OwnerTestDeps({
    FakeOwnerAuth? auth,
    FakeOwner? owner,
    FakeRatings? ratings,
    FakeRecon? recon,
    FakeOwnerNotifications? notifications,
    RecordingOwnerNav? nav,
    FakeOwnerMap? map,
    FakeLauncher? launcher,
  })  : auth = auth ?? FakeOwnerAuth(),
        launcher = launcher ?? FakeLauncher(),
        map = map ?? FakeOwnerMap(),
        owner = owner ?? FakeOwner(),
        ratings = ratings ?? FakeRatings(),
        recon = recon ?? FakeRecon(),
        notifications = notifications ?? FakeOwnerNotifications(),
        nav = nav ?? RecordingOwnerNav();

  final FakeOwnerAuth auth;
  final FakeOwner owner;
  final FakeRatings ratings;
  final FakeRecon recon;
  final FakeOwnerNotifications notifications;
  final RecordingOwnerNav nav;
  final FakeOwnerMap map;
  final FakeLauncher launcher;

  late final OwnerDataController data =
      OwnerDataController(owner, auth, now: () => ownerNow);
}

/// The app around an owner page: app theme (so the pages' own redesign
/// theme is exercised), providers and the nav scope above the navigator.
/// [withData] provides the deps' [OwnerDataController] (pages pushed from a
/// shell get it from [OwnerNav.push]); the shell creates its own.
Widget ownerApp(
  OwnerTestDeps deps,
  Widget home, {
  Locale locale = const Locale('en'),
  bool withData = true,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: deps.auth),
      ChangeNotifierProvider<OwnerProvider>.value(value: deps.owner),
      ChangeNotifierProvider<MarketplaceProvider>.value(value: deps.ratings),
      ChangeNotifierProvider<ReconciliationProvider>.value(value: deps.recon),
      ChangeNotifierProvider<NotificationsProvider>.value(
          value: deps.notifications),
      ChangeNotifierProvider<MapTrackingProvider>.value(value: deps.map),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => _FakeTheme()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      if (withData)
        ChangeNotifierProvider<OwnerDataController>.value(value: deps.data),
    ],
    child: OwnerNavScope(
      nav: deps.nav,
      child: CustomerMapTilesScope(
        tileProvider: BlankTileProvider(),
        child: QdLauncherScope(
          launcher: deps.launcher,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: quickDeliveryTheme,
            darkTheme: quickDeliveryDarkTheme,
            themeMode: ThemeMode.light,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: QdThemeScope(child: home),
          ),
        ),
      ),
    ),
  );
}

/// Pumps [home] after one controller refresh, so the page shows loaded data.
Future<void> pumpOwner(WidgetTester tester, OwnerTestDeps deps, Widget home,
    {Locale locale = const Locale('en'), bool refresh = true}) async {
  if (refresh) await deps.data.refresh();
  await tester.pumpWidget(ownerApp(deps, home, locale: locale));
  await tester.pumpAndSettle();
}

Job copyJob(Job j, {String? status, String? reason, String? requestStatus}) =>
    Job(
      id: j.id,
      ownerId: j.ownerId,
      employeeId: j.employeeId,
      userId: j.userId,
      serviceId: j.serviceId,
      status: status ?? j.status,
      location: j.location,
      destination: j.destination,
      paymentMethod: j.paymentMethod,
      cancellationReason: reason ?? j.cancellationReason,
      lockedEscrowAmount: j.lockedEscrowAmount,
      suggestedPrice: j.suggestedPrice,
      proposedPrice: j.proposedPrice,
      proposedBy: j.proposedBy,
      agreedPrice: j.agreedPrice,
      currentOfferedEmployeeId: j.currentOfferedEmployeeId,
      cancellationRequestReason: j.cancellationRequestReason,
      cancellationRequestedAt: j.cancellationRequestedAt,
      cancellationRequestStatus: requestStatus ?? j.cancellationRequestStatus,
      createdAt: j.createdAt,
    );

Job ownerJob({
  String id = 'a1b2c3d4e5f6',
  String status = 'active',
  String? employeeId = 'emp-1',
  String payment = 'cod',
  String? pickupNote = 'Beside the kiosk',
  String? dropNote = 'Zamalek, 26th of July St',
  double? price = 42,
  double? agreed,
  double? proposed,
  String? proposedBy,
  double? held,
  DateTime? createdAt,
  String? requestStatus,
  String? requestReason,
  DateTime? requestedAt,
  String? offeredTo,
  String? cancelReason,
  String userId = 'cust-9f8e7d',
  String? subStatus,
  List<JobStatusHistoryEntry> history = const [],
  int? etaMinutes,
  JobRecipient? recipient,
  JobPackageDetails? package,
  String? courierPhone,
  String? pickupAddress,
  String? dropAddress,
  String serviceId = 'svc-1',
}) =>
    Job(
      id: id,
      ownerId: 'owner-1',
      employeeId: employeeId,
      userId: userId,
      serviceId: serviceId,
      status: status,
      subStatus: subStatus,
      statusHistory: history,
      estimatedDurationMinutes: etaMinutes,
      recipient: recipient,
      packageDetails: package,
      courierPhone: courierPhone,
      location: JobLocation(
          latitude: 30.05,
          longitude: 31.24,
          addressNote: pickupNote,
          address: pickupAddress),
      destination: JobLocation(
          latitude: 30.06,
          longitude: 31.22,
          addressNote: dropNote,
          address: dropAddress),
      paymentMethod: payment,
      suggestedPrice: price,
      agreedPrice: agreed,
      proposedPrice: proposed,
      proposedBy: proposedBy,
      lockedEscrowAmount: held,
      createdAt: createdAt ?? ownerNow.subtract(const Duration(hours: 1)),
      cancellationRequestStatus: requestStatus,
      cancellationRequestReason: requestReason,
      cancellationRequestedAt: requestedAt,
      currentOfferedEmployeeId: offeredTo,
      cancellationReason: cancelReason,
    );

Map<String, dynamic> staff(String id, String name,
        {bool active = true, String? email}) =>
    {
      'id': id,
      'username': name,
      'email': email ?? '${name.toLowerCase()}@example.com',
      'is_active': active,
      'created_at': '2026-09-01T10:00:00Z',
    };

ReconciliationJob reconJob({
  String id = 'r1s2t3u4v5w6',
  String reason = 'under_distance_mismatch',
  double held = 120,
  String note = 'tracked 1.2 km of 6.0 km booked',
  String? employeeId = 'emp-1',
}) =>
    ReconciliationJob(
      id: id,
      ownerId: 'owner-1',
      serviceId: 'svc-1',
      userId: 'cust-9f8e7d',
      employeeId: employeeId,
      status: 'escrow_reconciliation_required',
      location: JobLocation(latitude: 30.05, longitude: 31.24),
      paymentMethod: 'wallet',
      lockedEscrowAmount: held,
      reconciliationNote: note,
      escrowFailureReason: reason,
    );

ApiClientException apiErr(int status, [String message = 'Request failed']) =>
    ApiClientException(message, statusCode: status);

AppLocalizations lookupOwnerEn() => lookupAppLocalizations(const Locale('en'));
