import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/features/customer/customer_location.dart';
import 'package:frontend/features/customer/customer_nav.dart';
import 'package:frontend/features/customer/customer_theme.dart';
import 'package:frontend/features/customer/picker_page.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/chat_message.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/chat_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/theme_provider.dart';
import 'package:frontend/ui/tokens.dart';
import 'package:provider/provider.dart';

/// Shared fakes and pump helpers for the FE-CUST-1 page tests.

const ar = Locale('ar');
const en = Locale('en');
const bothLocales = [ar, en];

/// Fixed "now" for date labels in tests and goldens.
final DateTime fixedNow = DateTime(2026, 10, 19, 15, 30);

class FakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  UserProfile? user = UserProfile(
    id: 'user-1',
    email: 'customer@example.com',
    username: 'Mona',
    role: 'user',
    kycStatus: 'approved',
  );

  @override
  String? token = 'customer-jwt';

  @override
  bool isLoading = false;

  @override
  String? error;

  @override
  Future<void> fetchUserProfile() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BookCall {
  BookCall(this.args);
  final Map<String, Object?> args;
}

/// Marketplace fake: services / jobs / errors are set by the test; calls are
/// recorded. [servicesGate] / [jobsGate] / [bookGate] hold a call open until
/// the test completes them (loading states, double submit).
class FakeMarketplace extends ChangeNotifier implements MarketplaceProvider {
  @override
  List<MarketplaceService> services = [];

  @override
  List<Job> customerJobs = [];

  @override
  bool isLoading = false;

  @override
  String? error;

  List<MarketplaceService> nextServices = [];
  String? nextServicesError;
  List<Job> nextJobs = [];
  String? nextJobsError;
  Job? nextBookedJob;
  Object? nextBookError;

  Completer<void>? servicesGate;
  Completer<void>? jobsGate;
  Completer<void>? bookGate;

  final List<Map<String, Object?>> serviceCalls = [];
  int jobCalls = 0;
  final List<BookCall> bookCalls = [];

  @override
  Future<void> fetchServices({
    bool nearBy = true,
    double lat = 30.0444,
    double lon = 31.2357,
    double radius = 50.0,
    String sortBy = 'price',
  }) async {
    serviceCalls.add({
      'nearBy': nearBy,
      'lat': lat,
      'lon': lon,
      'radius': radius,
      'sortBy': sortBy,
    });
    error = null;
    if (servicesGate != null) await servicesGate!.future;
    if (nextServicesError != null) {
      error = nextServicesError;
    } else {
      services = nextServices;
    }
    notifyListeners();
  }

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async {
    jobCalls++;
    error = null;
    if (jobsGate != null) await jobsGate!.future;
    if (nextJobsError != null) {
      error = nextJobsError;
      customerJobs = [];
    } else {
      customerJobs = nextJobs;
    }
    notifyListeners();
    return customerJobs;
  }

  @override
  Future<Job?> bookJob({
    required String serviceId,
    required String userId,
    required double latitude,
    required double longitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required String paymentMethod,
    String? pickupAddressNote,
    String? destinationAddressNote,
  }) async {
    bookCalls.add(BookCall({
      'serviceId': serviceId,
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      'destinationLatitude': destinationLatitude,
      'destinationLongitude': destinationLongitude,
      'paymentMethod': paymentMethod,
      'pickupAddressNote': pickupAddressNote,
      'destinationAddressNote': destinationAddressNote,
    }));
    if (bookGate != null) await bookGate!.future;
    if (nextBookError != null) throw nextBookError!;
    return nextBookedJob;
  }

  // --- Order detail (FE-CUST-2) ---

  /// What fetchJobStatus returns next; null = failure with [nextStatusError].
  Job? nextStatus;
  String? nextStatusError = 'Service unavailable';
  Completer<void>? statusGate;
  final List<String> statusCalls = [];

  @override
  Future<Job?> fetchJobStatus(String jobId, String userToken) async {
    statusCalls.add(jobId);
    error = null;
    if (statusGate != null) await statusGate!.future;
    if (nextStatus == null) {
      error = nextStatusError;
      return null;
    }
    return nextStatus;
  }

  final List<Map<String, Object?>> cancelCalls = [];
  Object? nextCancelError;

  @override
  Future<Map<String, dynamic>> cancelJob({
    required String jobId,
    required String reason,
    required String userToken,
  }) async {
    cancelCalls.add({'jobId': jobId, 'reason': reason, 'token': userToken});
    if (nextCancelError != null) throw nextCancelError!;
    return {'status': 'cancelled'};
  }

  final List<Map<String, Object?>> proposeCalls = [];
  final List<Map<String, Object?>> respondCalls = [];
  Object? nextPriceError;
  Job? nextPriceJob;

  @override
  Future<Job?> proposePrice({
    required String jobId,
    required double proposedPrice,
    required String userToken,
  }) async {
    proposeCalls.add({'jobId': jobId, 'price': proposedPrice});
    if (nextPriceError != null) throw nextPriceError!;
    return nextPriceJob;
  }

  @override
  Future<Job?> respondPrice({
    required String jobId,
    required String decision,
    required String userToken,
  }) async {
    respondCalls.add({'jobId': jobId, 'decision': decision});
    if (nextPriceError != null) throw nextPriceError!;
    return nextPriceJob;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeNotifications extends ChangeNotifier
    implements NotificationsProvider {
  @override
  int unreadCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeThemeProvider extends ChangeNotifier implements ThemeProvider {
  @override
  ThemeMode themeMode = ThemeMode.light;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeChat extends ChangeNotifier implements ChatProvider {
  @override
  bool isLoadingHistory = false;

  @override
  List<ChatMessage> messages = [];

  @override
  bool isConnected = false;

  @override
  bool isConnecting = false;

  @override
  String? error;

  @override
  String? subscriptionError;

  /// What the next history fetch does: messages, an error, a refusal.
  List<ChatMessage> nextHistory = [];
  String? nextHistoryError;
  bool nextHistoryDenied = false;
  Completer<void>? historyGate;
  Object? nextSendError;
  Completer<void>? sendGate;

  final List<String> historyCalls = [];
  final List<String> connectCalls = [];
  final List<String> sent = [];
  int disconnects = 0;

  @override
  Future<void> fetchChannelHistory(String channel, String token) async {
    historyCalls.add(channel);
    error = null;
    subscriptionError = null;
    messages = [];
    isLoadingHistory = true;
    notifyListeners();
    if (historyGate != null) await historyGate!.future;
    isLoadingHistory = false;
    if (nextHistoryDenied) {
      error = 'denied';
      subscriptionError = 'not authorized for this channel';
    } else if (nextHistoryError != null) {
      error = nextHistoryError;
    } else {
      messages = List.of(nextHistory);
    }
    notifyListeners();
  }

  @override
  void connectAndSubscribeChannel(String channel, String token) {
    connectCalls.add(channel);
    isConnected = true;
    notifyListeners();
  }

  @override
  Future<void> sendMessage(String content) async {
    sent.add(content);
    if (sendGate != null) await sendGate!.future;
    if (nextSendError != null) throw nextSendError!;
  }

  @override
  void disconnect() {
    disconnects++;
    isConnected = false;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Live map fake: tests set markers / connection state; calls recorded.
class FakeMapTracking extends ChangeNotifier implements MapTrackingProvider {
  @override
  List<EmployeeMarkerData> markersList = [];

  @override
  JobLocation? customerJobLocation;

  @override
  JobLocation? customerJobDestination;

  @override
  bool isLoading = false;

  @override
  bool isConnected = true;

  @override
  String? subscriptionError;

  final List<String> hydrateCalls = [];
  final List<String> subscribeCalls = [];
  int disconnects = 0;

  @override
  Future<void> hydrateCustomerJob(String jobId, String userToken) async {
    hydrateCalls.add(jobId);
    notifyListeners();
  }

  @override
  void connectAndSubscribe(String channel, String token,
      {Object? customChannel}) {
    subscribeCalls.add(channel);
    notifyListeners();
  }

  @override
  void disconnect() {
    disconnects++;
  }

  void setCourier(double lat, double lon, {String id = 'emp-1'}) {
    markersList = [
      EmployeeMarkerData(
          employeeId: id,
          jobId: null,
          latitude: lat,
          longitude: lon,
          updatedAt: fixedNow),
    ];
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocator extends CustomerLocator {
  FakeLocator([this.result = const LocateResult.found(30.05, 31.24)]);

  LocateResult result;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<LocateResult> locate() async {
    calls++;
    if (gate != null) await gate!.future;
    return result;
  }
}

/// Records hand-offs to screens that are not rebuilt (order detail,
/// notifications) instead of pushing them.
class RecordingNav extends CustomerNav {
  final List<(Job, bool)> openedOrders = [];
  int notificationsOpened = 0;

  @override
  Future<void> openOrder(BuildContext context, Job job,
      {bool replaceStack = false}) async {
    openedOrders.add((job, replaceStack));
  }

  @override
  Future<void> openNotifications(BuildContext context) async {
    notificationsOpened++;
  }
}

class CustomerTestDeps {
  CustomerTestDeps({
    FakeAuth? auth,
    FakeMarketplace? marketplace,
    FakeNotifications? notifications,
    FakeLocator? locator,
    RecordingNav? nav,
    FakeChat? chat,
    FakeMapTracking? map,
  })  : chat = chat ?? FakeChat(),
        map = map ?? FakeMapTracking(),
        auth = auth ?? FakeAuth(),
        marketplace = marketplace ?? FakeMarketplace(),
        notifications = notifications ?? FakeNotifications(),
        locator = locator ?? FakeLocator(),
        nav = nav ?? RecordingNav();

  final FakeAuth auth;
  final FakeMarketplace marketplace;
  final FakeNotifications notifications;
  final FakeLocator locator;
  final RecordingNav nav;
  final FakeChat chat;
  final FakeMapTracking map;
}

/// The app around a customer page: real app theme (so [CustomerTheme] is
/// exercised), providers, map tiles, locator and nav scopes above the
/// navigator.
Widget customerApp(
  CustomerTestDeps deps,
  Widget home, {
  Locale locale = en,
  bool wrapTheme = true,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: deps.auth),
      ChangeNotifierProvider<MarketplaceProvider>.value(
          value: deps.marketplace),
      ChangeNotifierProvider<NotificationsProvider>.value(
          value: deps.notifications),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => FakeThemeProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
      ChangeNotifierProvider<ChatProvider>.value(value: deps.chat),
      ChangeNotifierProvider<MapTrackingProvider>.value(value: deps.map),
    ],
    child: CustomerMapTilesScope(
      tileProvider: BlankTileProvider(),
      child: CustomerLocatorScope(
        locator: deps.locator,
        child: CustomerNavScope(
          nav: deps.nav,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: quickDeliveryTheme,
            darkTheme: quickDeliveryDarkTheme,
            themeMode: themeMode,
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: wrapTheme ? CustomerTheme(child: home) : home,
          ),
        ),
      ),
    ),
  );
}

/// 1x1 transparent PNG.
final Uint8List _blankPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x60,
  0x60,
  0x60,
  0x60,
  0x00,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0xA5,
  0xF6,
  0x45,
  0x40,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Map tiles that never touch the network: every tile is blank.
class BlankTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_blankPng);
}

/// 360x800 phone viewport at 1.0 DPR.
void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Loads the bundled Plex font so goldens show real Arabic shaping.
Future<void> loadPlexFont() async {
  final loader = FontLoader(kQdFontFamily);
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes =
        File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

MarketplaceService service({
  String id = 'svc-1',
  String name = 'Nile Express',
  String category = 'delivery',
  double base = 20,
  double tenantBase = 25,
  double perKm = 5,
  double distanceKm = 2.4,
  double finalPrice = 37,
  bool? open = true,
  DateTime? reopensAt,
}) =>
    MarketplaceService(
      id: id,
      tenantId: 'tenant-$id',
      name: name,
      category: category,
      basePrice: base,
      tenantBasePrice: tenantBase,
      tenantPricePerKM: perKm,
      latitude: 30.05,
      longitude: 31.24,
      distanceKM: distanceKm,
      finalPrice: finalPrice,
      isOpenNow: open,
      reopensAt: reopensAt,
    );

Job job({
  String id = 'a1b2c3d4e5f6',
  String status = 'active',
  String serviceId = 'svc-1',
  String? pickupNote = 'Beside the kiosk',
  String? dropNote = 'Zamalek, 26th of July St',
  double? price = 42,
  DateTime? createdAt,
  String? cancellationRequestStatus,
}) =>
    Job(
      id: id,
      ownerId: 'tenant-svc-1',
      userId: 'user-1',
      serviceId: serviceId,
      status: status,
      location: JobLocation(
          latitude: 30.05, longitude: 31.24, addressNote: pickupNote),
      destination:
          JobLocation(latitude: 30.06, longitude: 31.22, addressNote: dropNote),
      paymentMethod: 'cod',
      suggestedPrice: price,
      createdAt: createdAt ?? fixedNow.subtract(const Duration(hours: 1)),
      cancellationRequestStatus: cancellationRequestStatus,
    );

/// An ApiClientException as the provider would surface it.
ApiClientException apiError([String message = 'Service unavailable']) =>
    ApiClientException(message, statusCode: 503);

/// English strings outside a widget tree.
AppLocalizations lookupEn() => lookupAppLocalizations(en);
