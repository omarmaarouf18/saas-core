import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/features/courier/courier_controller.dart';
import 'package:frontend/features/courier/courier_nav.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/notification_model.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/employee_jobs_provider.dart';
import 'package:frontend/providers/employee_location_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/ui/qd_ui.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../customer/customer_harness.dart' show BlankTileProvider, en;

export '../customer/customer_harness.dart'
    show ar, en, bothLocales, usePhone, loadPlexFont;

/// Shared fakes and pump helpers for the FE-COURIER page tests.

/// Fixed "now" for countdowns, "today" and goldens.
final DateTime courierNow = DateTime(2026, 10, 19, 15, 30);

class FakeCourierAuth extends ChangeNotifier implements AuthProvider {
  FakeCourierAuth({
    String? kyeStatus = 'approved',
    String? accountStatus = 'active',
    String? suspensionReason,
    String? rejectionReason,
  }) : user = UserProfile(
          id: 'emp-1',
          email: 'karim@example.com',
          username: 'Karim',
          role: 'employee',
          kyeStatus: kyeStatus,
          accountStatus: accountStatus,
          suspensionReason: suspensionReason,
          rejectionReason: rejectionReason,
        );

  @override
  UserProfile? user;

  @override
  String? token = 'courier-jwt';

  @override
  bool isLoading = false;

  @override
  String? error;

  int profileCalls = 0;

  /// What the next profile fetch turns the user into (null: unchanged).
  UserProfile? nextUser;

  @override
  Future<void> fetchUserProfile() async {
    profileCalls++;
    if (nextUser != null) {
      user = nextUser;
      notifyListeners();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One recorded provider call.
class Call {
  Call(this.name, [this.args = const {}]);
  final String name;
  final Map<String, Object?> args;

  @override
  String toString() => '$name$args';
}

/// EmployeeJobsProvider fake: the test sets what the next fetch returns and
/// what an action throws; every call is recorded. A gate holds a call open.
class FakeEmployeeJobs extends ChangeNotifier implements EmployeeJobsProvider {
  @override
  List<Job> jobs = [];

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  int? lastErrorStatusCode;

  List<Job> nextJobs = [];
  String? nextFetchError;
  Completer<void>? fetchGate;
  int fetchCalls = 0;

  final List<Call> calls = [];

  /// Thrown by the next action call (then cleared).
  Object? nextActionError;
  Completer<void>? actionGate;

  /// Jobs after a successful action (applied, then a refetch returns them).
  List<Job>? jobsAfterAction;

  void seed(List<Job> list) => jobs = nextJobs = List.of(list);

  @override
  Future<void> fetchAssignedJobs(String employeeToken) async {
    fetchCalls++;
    isLoading = true;
    notifyListeners();
    if (fetchGate != null) await fetchGate!.future;
    isLoading = false;
    if (nextFetchError != null) {
      error = nextFetchError;
    } else {
      error = null;
      jobs = List.of(nextJobs);
    }
    notifyListeners();
  }

  Future<void> _act(String name, Map<String, Object?> args) async {
    calls.add(Call(name, args));
    if (actionGate != null) await actionGate!.future;
    final err = nextActionError;
    if (err != null) {
      nextActionError = null;
      lastErrorStatusCode = err is ApiClientException ? err.statusCode : null;
      throw err;
    }
    if (jobsAfterAction != null) {
      nextJobs = jobsAfterAction!;
      jobs = List.of(nextJobs);
      notifyListeners();
    }
  }

  @override
  Future<void> acceptJobOffer(String jobId) => _act('accept', {'job': jobId});

  @override
  Future<void> declineJobOffer(String jobId) => _act('decline', {'job': jobId});

  @override
  Future<void> completeJob(String jobId, {bool cashCollected = false}) =>
      _act('complete', {'job': jobId, 'cash': cashCollected});

  @override
  Future<Map<String, dynamic>> requestCancellation({
    required String jobId,
    required String reason,
    required String employeeToken,
  }) async {
    await _act('requestCancellation', {'job': jobId, 'reason': reason});
    return {'cancellation_request_status': 'pending'};
  }

  @override
  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String employeeToken,
  }) async {
    await _act('respondPrice', {'job': jobId, 'decision': decision});
    return null;
  }

  @override
  Future<Job?> proposePrice({
    required String jobId,
    required double proposedPrice,
    required String employeeToken,
  }) async {
    await _act('proposePrice', {'job': jobId, 'price': proposedPrice});
    return null;
  }

  @override
  void clearError() {
    error = null;
    lastErrorStatusCode = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// EmployeeLocationProvider fake (no GPS, no network): records the tracking
/// calls the controller makes.
class FakeCourierLocation extends ChangeNotifier
    implements EmployeeLocationProvider {
  @override
  LocationSharingStatus status = LocationSharingStatus.tracking;

  @override
  String? error;

  @override
  bool isAvailableOnline = true;

  @override
  Position? lastKnownPosition;

  @override
  String? activeJobId;

  @override
  bool get isTracking => status == LocationSharingStatus.tracking;

  @override
  bool get isAvailable => isAvailableOnline;

  final List<Call> calls = [];

  @override
  Future<void> startTracking(String jobId, String userToken) async {
    calls.add(Call('track', {'job': jobId}));
    activeJobId = jobId;
  }

  @override
  Future<void> startAvailabilityTracking(String userToken) async {
    calls.add(Call('availability'));
    activeJobId = null;
  }

  @override
  Future<void> stopAvailabilityTracking() async {
    calls.add(Call('stopAvailability'));
  }

  @override
  Future<void> stopTracking({bool notify = true}) async {
    calls.add(Call('stop'));
    activeJobId = null;
  }

  @override
  Future<void> setAvailableOnline(bool online, {String? userToken}) async {
    calls.add(Call('setOnline', {'online': online}));
    isAvailableOnline = online;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A position at [lat], [lng] (for the "you" marker and distances).
Position position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: courierNow,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class FakeCourierNotifications extends ChangeNotifier
    implements NotificationsProvider {
  @override
  List<NotificationModel> notifications = [];

  @override
  int get unreadCount => notifications.where((n) => !n.isRead).length;

  void push(NotificationModel n) {
    notifications = [n, ...notifications];
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NotificationModel notification(String id, {String type = 'job_alert'}) =>
    NotificationModel(
      id: id,
      type: type,
      tenantId: 't',
      title: 'New order',
      body: 'A new order is waiting',
      timestamp: courierNow,
    );

class _FakeTheme extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records hand-offs to screens that are not rebuilt (document upload,
/// notifications, support, chat, sign out). Redesigned pages are still
/// pushed for real.
class RecordingCourierNav extends CourierNav {
  final List<String> opened = [];

  @override
  Future<void> openVerification(BuildContext context) async =>
      opened.add('verification');

  @override
  Future<void> openNotifications(BuildContext context) async =>
      opened.add('notifications');

  @override
  Future<void> openChat(BuildContext context, Job job) async =>
      opened.add('chat:${job.id}');

  @override
  Future<void> openSupport(BuildContext context) async => opened.add('support');

  @override
  Future<void> signOut(BuildContext context) async => opened.add('sign_out');
}

class CourierTestDeps {
  CourierTestDeps({
    FakeCourierAuth? auth,
    FakeEmployeeJobs? jobs,
    FakeCourierLocation? location,
    FakeCourierNotifications? notifications,
    RecordingCourierNav? nav,
  })  : auth = auth ?? FakeCourierAuth(),
        jobs = jobs ?? FakeEmployeeJobs(),
        location = location ?? FakeCourierLocation(),
        notifications = notifications ?? FakeCourierNotifications(),
        nav = nav ?? RecordingCourierNav();

  final FakeCourierAuth auth;
  final FakeEmployeeJobs jobs;
  final FakeCourierLocation location;
  final FakeCourierNotifications notifications;
  final RecordingCourierNav nav;

  /// The controller's clock; tests move it to cross an expiry.
  DateTime clock = courierNow;

  late final CourierController controller = CourierController(
    jobsProvider: jobs,
    location: location,
    auth: auth,
    now: () => clock,
  );
}

/// The app around a courier page: app theme (so the pages' own redesign
/// theme is exercised), providers, blank map tiles and the nav scope.
/// [withController] provides the deps' [CourierController] (the shell
/// creates its own).
Widget courierApp(
  CourierTestDeps deps,
  Widget home, {
  Locale locale = const Locale('en'),
  bool withController = true,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: deps.auth),
      ChangeNotifierProvider<EmployeeJobsProvider>.value(value: deps.jobs),
      ChangeNotifierProvider<EmployeeLocationProvider>.value(
          value: deps.location),
      ChangeNotifierProvider<NotificationsProvider>.value(
          value: deps.notifications),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => _FakeTheme()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      if (withController)
        ChangeNotifierProvider<CourierController>.value(value: deps.controller),
    ],
    child: CourierNavScope(
      nav: deps.nav,
      child: CustomerMapTilesScope(
        tileProvider: BlankTileProvider(),
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
  );
}

/// Pumps [home] after one controller refresh, so the page shows loaded data.
Future<void> pumpCourier(WidgetTester tester, CourierTestDeps deps, Widget home,
    {Locale locale = const Locale('en'), bool refresh = true}) async {
  if (refresh) await deps.controller.refresh();
  await tester.pumpWidget(courierApp(deps, home, locale: locale));
  await tester.pump();
}

/// A courier-side job (COD, Cairo coordinates) with v2 fields as given.
Job courierJob({
  String id = 'a1b2c3d4e5f6',
  String status = 'active',
  String? subStatus,
  String payment = 'cod',
  String? pickupAddress,
  String? pickupNote = 'Beside the kiosk',
  String? dropAddress,
  String? dropNote = 'Zamalek, 26th of July St',
  bool withDestination = true,
  double? price = 42,
  double? agreed,
  double? proposed,
  String? proposedBy,
  DateTime? proposalExpiresAt,
  DateTime? offerExpiresAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? requestStatus,
  String? cancelReason,
  JobRecipient? recipient,
  JobPackageDetails? package,
  List<JobStatusHistoryEntry> history = const [],
}) =>
    Job(
      id: id,
      ownerId: 'owner-1',
      employeeId: status == 'pending_dispatch' ? null : 'emp-1',
      userId: 'user-1',
      serviceId: 'svc-1',
      status: status,
      subStatus: subStatus,
      location: JobLocation(
          latitude: 30.0444,
          longitude: 31.2357,
          address: pickupAddress,
          addressNote: pickupNote),
      destination: withDestination
          ? JobLocation(
              latitude: 30.0600,
              longitude: 31.2200,
              address: dropAddress,
              addressNote: dropNote)
          : null,
      paymentMethod: payment,
      suggestedPrice: price,
      agreedPrice: agreed,
      proposedPrice: proposed,
      proposedBy: proposedBy,
      priceProposalExpiresAt: proposalExpiresAt,
      currentOfferedEmployeeId: status == 'pending_dispatch' ? 'emp-1' : null,
      offerExpiresAt: offerExpiresAt,
      cancellationReason: cancelReason,
      cancellationRequestStatus: requestStatus,
      createdAt: createdAt ?? courierNow.subtract(const Duration(hours: 1)),
      updatedAt: updatedAt,
      recipient: recipient,
      packageDetails: package,
      statusHistory: history,
    );

/// An ApiClientException as the provider would surface it.
ApiClientException courierApiError(int status, [String message = 'error']) =>
    ApiClientException(message, statusCode: status);

/// English strings outside a widget tree.
AppLocalizations courierEn() => lookupAppLocalizations(en);
