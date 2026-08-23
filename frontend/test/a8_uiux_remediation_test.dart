import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/models/job.dart' show Job, JobLocation;
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/providers/notifications_provider.dart';
import 'package:frontend/screens/customer_home_screen.dart';
import 'package:frontend/screens/job_status_screen.dart';
import 'package:frontend/widgets/otp_pin_input.dart';
import 'package:frontend/widgets/pill_filter_bar.dart';
import 'package:frontend/models/user_profile.dart';
import 'package:provider/provider.dart';

/// QA audit A8 (UI_UX_AUDIT.md) remediation regression tests.
///
/// B1-F1: customer home must surface marketplace fetch failures.
/// B4-F1: counter-offer row must not overflow at narrow widths and must
///        stack below the 340dp threshold.
/// A3-F1: OTP boxes expose per-digit semantics labels.

Widget _l10nApp({required Widget child}) => MaterialApp(
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

class _StubMarketplaceProvider extends MarketplaceProvider {
  final String? stubError;
  _StubMarketplaceProvider(super.apiClient, {String? error})
      : stubError = error;

  @override
  List<Job> get customerJobs => const [];

  @override
  String? get error => stubError;

  @override
  Future<List<Job>> fetchCustomerJobs([String? userToken]) async => const [];
}

class _StubAuthProvider extends AuthProvider {
  _StubAuthProvider(super.apiClient);

  @override
  UserProfile? get user => UserProfile(
        id: 'a8-user',
        email: 'a8@test.local',
        username: 'a8tester',
        role: 'customer',
      );

  @override
  String? get token => 'token-a8';
}

void main() {
  group('A8/B1-F1: customer home activity error surface', () {
    testWidgets('shows retryable banner when the marketplace fetch failed',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      final marketplace = _StubMarketplaceProvider(ApiClient(),
          error: 'Service temporarily unavailable');

      await tester.pumpWidget(
        _l10nApp(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(
                  value: _StubAuthProvider(ApiClient())),
              ChangeNotifierProvider<MarketplaceProvider>.value(
                  value: marketplace),
              ChangeNotifierProvider<NotificationsProvider>(
                create: (_) => NotificationsProvider(ApiClient()),
              ),
            ],
            child: const CustomerHomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('customer_home_activity_error')),
          findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('no error banner when the fetch succeeded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      final marketplace = _StubMarketplaceProvider(ApiClient(), error: null);

      await tester.pumpWidget(
        _l10nApp(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(
                  value: _StubAuthProvider(ApiClient())),
              ChangeNotifierProvider<MarketplaceProvider>.value(
                  value: marketplace),
              ChangeNotifierProvider<NotificationsProvider>(
                create: (_) => NotificationsProvider(ApiClient()),
              ),
            ],
            child: const CustomerHomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(
          find.byKey(const Key('customer_home_activity_error')), findsNothing);
      expect(find.textContaining('temporarily unavailable'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });
  });

  group('A8/B4-F1: counter-offer input + submit layout', () {
    final baseJob = Job(
      id: 'job-transport-a8',
      ownerId: 'owner-1',
      employeeId: 'employee-1',
      userId: 'customer-1',
      serviceId: 'service-transport-1',
      status: 'awaiting_price_response',
      location: JobLocation(latitude: 30.0444, longitude: 31.2357),
      paymentMethod: 'cod',
      suggestedPrice: 20.0,
      priceProposalExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

    Future<void> pumpJobStatus(WidgetTester tester, Size size) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _l10nApp(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(
                  value: _StubAuthProvider(ApiClient())),
              ChangeNotifierProvider<MarketplaceProvider>.value(
                  value: MarketplaceProvider(ApiClient())),
            ],
            child: SizedBox(
                width: size.width,
                child: JobStatusScreen(job: baseJob, enablePolling: false)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders without overflow at 320dp (stacked layout)',
        (tester) async {
      // A RenderFlex overflow throws in widget tests; a clean pump proves
      // the LayoutBuilder stack path holds at sub-360dp widths.
      await pumpJobStatus(tester, const Size(320, 900));
      expect(find.byKey(const Key('submit_proposal_button')), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('renders without overflow at 360dp (stacked threshold edge)',
        (tester) async {
      await pumpJobStatus(tester, const Size(360, 900));
      expect(find.byKey(const Key('submit_proposal_button')), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('A8/A3-F1: OTP per-digit semantics', () {
    testWidgets('each PIN box exposes an index-aware semantics label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_l10nApp(
        child: Scaffold(
          body: Center(child: OtpPinInput(onChanged: (_) {})),
        ),
      ));
      await tester.pump();

      expect(find.bySemanticsLabel('PIN digit 1 of 6'), findsOneWidget);
      expect(find.bySemanticsLabel('PIN digit 6 of 6'), findsOneWidget);
      handle.dispose();
    });
  });

  group('A8/Tier3: pill filter bar RTL safety', () {
    testWidgets('renders under right-to-left directionality', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: Scaffold(
              body: PillFilterBar<String>(
                items: const [
                  PillFilterItem(label: 'All', value: 'all'),
                  PillFilterItem(label: 'Active', value: 'active'),
                ],
                selectedValue: 'all',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('All'), findsOneWidget);
    });
  });
}
