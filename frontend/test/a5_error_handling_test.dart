import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/core/error_messages.dart';
import 'package:frontend/core/update_gate.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/models/marketplace_service.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/locale_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/customer_marketplace_screen.dart';
import 'package:frontend/screens/subscription_screen.dart';
import 'package:frontend/screens/update_required_screen.dart';
import 'package:frontend/widgets/create_service_dialog.dart';

import 'helpers/mock_http_harness.dart';

/// QA audit A5 regression tests: error-handling consistency.
///
/// Every test simulates a failure (mock transport or throwing provider
/// override) and asserts the USER-VISIBLE OUTCOME — friendly actionable copy
/// on screen, an error banner replacing a lying empty state, or the forced-
/// update gate navigating — never merely "no crash".

Widget _localize(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('ApiClient request timeout (A5 systemic fix)', () {
    test('a hung backend surfaces as TimeoutException, not an eternal await',
        () async {
      installMockHttp((req) {
        // Never respond — the exact hang the timeout exists for.
        return Completer<MockHttpResponse>().future;
      });
      final api = ApiClient(
        baseUrl: 'https://ci.local/api/v1',
        requestTimeout: const Duration(milliseconds: 80),
      );

      await expectLater(
        api.get('/users/services'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('POST times out identically', () async {
      installMockHttp((req) => Completer<MockHttpResponse>().future);
      final api = ApiClient(
        baseUrl: 'https://ci.local/api/v1',
        requestTimeout: const Duration(milliseconds: 80),
      );

      await expectLater(
        api.post('/users/jobs', {'job_id': 'x'}),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('friendlyErrorMessage maps TimeoutException to connectivity copy',
        () {
      expect(
        friendlyErrorMessage(TimeoutException('deadline exceeded')),
        ErrorMessages.connectionError,
      );
    });
  });

  group('HTTP 426 forced-update gate (A5 dead-code fix)', () {
    test('transport fires onUpdateRequired and throws a 426 exception',
        () async {
      Map<String, dynamic>? received;
      final overrides = installMockHttp((req) => MockHttpResponse(426,
          jsonBody: {'minimum_version': '2.0.0'}));
      final api = ApiClient(baseUrl: 'https://ci.local/api/v1')
        ..onUpdateRequired = (info) async => received = info;

      await expectLater(
        api.get('/users/wallet'),
        throwsA(isA<ApiClientException>()
            .having((e) => e.statusCode, 'statusCode', 426)),
      );
      expect(received?['minimum_version'], '2.0.0');
      expect(overrides.requests, isNotEmpty);
    });

    testWidgets('gate navigates to UpdateRequiredScreen exactly once',
        (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final gate = UpdateGate(navigatorKey);

      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider()),
      ], child: MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('HOME-MARKER'))),
      )));

      await gate.handle({
        'minimum_version': '2.0.0',
        'download_url': 'https://x/app.apk',
      });
      await tester.pumpAndSettle();

      expect(find.byType(UpdateRequiredScreen), findsOneWidget);

      // A second failing call during the same session must NOT stack
      // another gate.
      await gate.handle({'minimum_version': '2.0.0'});
      await tester.pumpAndSettle();
      expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    });
  });

  group('Marketplace fetch failure no longer masquerades as empty state',
      () {
    testWidgets('backend outage shows retryable banner, not "no services"',
        (tester) async {
      final failingProvider = _FailingMarketplaceProvider(ApiClient());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(ApiClient())),
          ChangeNotifierProvider<MarketplaceProvider>.value(
              value: failingProvider),
        ],
        child: MultiProvider(providers: [
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => NotificationsProvider(ApiClient())),
        ], child: _localize(const CustomerMarketplaceScreen())),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('marketplace_error_banner')),
          findsOneWidget);
      expect(find.textContaining('No services found nearby'), findsNothing,
          reason: 'an outage must not be presented as "no couriers exist"');
    });
  });

  group('Booking failure shows friendly message, not raw exception dump', () {
    testWidgets(
        'confirm with a failing bookJob renders mapped status text only',
        (tester) async {
      final provider =
          _BookingFailingMarketplaceProvider(ApiClient(), _serviceFixture());

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
              value: _StubAuthProvider(ApiClient())),
          ChangeNotifierProvider<MarketplaceProvider>.value(
              value: provider),
          ChangeNotifierProvider<NotificationsProvider>(
              create: (_) => NotificationsProvider(ApiClient())),
        ],
        child: _localize(const CustomerMarketplaceScreen()),
      ));
      await tester.pumpAndSettle();

      final bookBtn = find.text('Book');
      await tester.scrollUntilVisible(bookBtn, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(bookBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_booking_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('Booking Failed: Please check your input and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('ApiClientException'), findsNothing);
      expect(find.textContaining('insufficient wallet balance'),
          findsNothing,
          reason: 'non-auth flows intentionally map by status code; the raw '
              'backend string must not reach the snackbar');
    });
  });

  group('Subscription change failure stops reusing the rating copy', () {
    testWidgets('failed upgrade shows server-error copy without "Error:" dump',
        (tester) async {
      final owner = _SubscriptionThrowingOwnerProvider(ApiClient());
      final auth = _StubAuthProvider(ApiClient(),
          user: UserProfile(
            id: 'owner-1',
            email: 'o@x.dev',
            username: 'owner',
            role: 'owner',
            kycStatus: 'approved',
          ));

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<OwnerProvider>.value(value: owner),
        ],
        child: _localize(const SubscriptionScreen()),
      ));
      await tester.pumpAndSettle();

      final upgradeBtn = find.text('Upgrade to Professional');
      await tester.ensureVisible(upgradeBtn);
      await tester.pumpAndSettle();
      await tester.tap(upgradeBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Something went wrong on our end'),
          findsOneWidget);
      expect(find.textContaining('Exception:'), findsNothing);
    });
  });

  group('Create-service dialog failure maps through friendly layer', () {
    testWidgets('duplicate-name style throw loses its raw Exception prefix',
        (tester) async {
      final owner = _CreateServiceThrowingOwnerProvider(ApiClient());

      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider<OwnerProvider>.value(value: owner),
      ], child: _localize(Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  CreateServiceDialog.show(ctx, ownerId: 'owner-test-1'),
              child: const Text('Open Create Service Dialog'),
            ),
          ),
        ),
      ))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Create Service Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('service_name_field')), 'Fresh Parcel Run');
      await tester.enterText(
          find.byKey(const Key('service_base_price_field')), '20.0');
      await tester.enterText(
          find.byKey(const Key('service_price_per_km_field')), '5.0');
      await tester.enterText(
          find.byKey(const Key('service_latitude_field')), '30.0444');
      await tester.enterText(
          find.byKey(const Key('service_longitude_field')), '31.2357');

      final submitBtn = find.byKey(const Key('service_create_button'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to create service'), findsOneWidget);
      expect(find.textContaining('Exception:'), findsNothing);
    });
  });

  group('verifyOtp token-less 2xx is no longer a silent dead-end', () {
    test('missing token in response sets visible fallback error', () async {
      installMockHttp(
          (req) => MockHttpResponse.ok({})); // 200 but no token field.
      final auth = AuthProvider(ApiClient(baseUrl: 'https://ci.local/api/v1'));

      final ok = await auth.verifyOtp('e@x.dev', '111222');

      expect(ok, isFalse);
      expect(auth.error, ErrorMessages.genericFallback,
          reason: 'otp_screen surfaces auth.error; null meant NOTHING was '
              'rendered after a successful-looking verification');
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures & mocks
// ---------------------------------------------------------------------------

MarketplaceService _serviceFixture() => MarketplaceService(
      id: 'svc-a5',
      tenantId: 'owner-1',
      name: 'Express Delivery',
      category: 'delivery',
      basePrice: 28.0,
      tenantBasePrice: 30.0,
      tenantPricePerKM: 5.0,
      latitude: 30.0444,
      longitude: 31.2357,
      distanceKM: 4.2,
      finalPrice: 35.0,
    );

class _StubAuthProvider extends AuthProvider {
  _StubAuthProvider(super.apiClient, {UserProfile? user});

  @override
  UserProfile? get user => UserProfile(
        id: 'cust-a5',
        email: 'c@x.dev',
        username: 'cust_a5',
        role: 'user',
      );

  @override
  String? get token => 'mock-token';
}

class _FailingMarketplaceProvider extends MarketplaceProvider {
  _FailingMarketplaceProvider(super.apiClient);

  @override
  List<MarketplaceService> get services => const [];

  @override
  bool get isLoading => false;

  @override
  String? get error => 'Something went wrong. Please try again.';
}

class _BookingFailingMarketplaceProvider extends MarketplaceProvider {
  _BookingFailingMarketplaceProvider(super.apiClient, this._service);

  final MarketplaceService _service;

  @override
  List<MarketplaceService> get services => [_service];

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  Future<Job?> bookJob({
    required String serviceId,
    required String userId,
    required double latitude,
    required double longitude,
    required String paymentMethod,
  }) async {
    throw ApiClientException('insufficient wallet balance', statusCode: 400);
  }
}

class _SubscriptionThrowingOwnerProvider extends OwnerProvider {
  _SubscriptionThrowingOwnerProvider(super.apiClient);

  @override
  String get subscriptionTier => 'free';

  @override
  Future<Map<String, dynamic>> updateSubscription({
    required String tenantId,
    required String tier,
  }) async {
    throw ApiClientException('server exploded', statusCode: 500);
  }
}

class _CreateServiceThrowingOwnerProvider extends OwnerProvider {
  _CreateServiceThrowingOwnerProvider(super.apiClient);

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
    throw Exception('Service name already exists');
  }
}
