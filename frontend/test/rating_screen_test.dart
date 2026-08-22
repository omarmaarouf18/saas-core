import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/providers/marketplace_provider.dart';
import 'package:frontend/screens/rating_screen.dart';

import 'helpers/mock_http_harness.dart';
import 'helpers/secure_storage_mock.dart';

/// Real providers over the mock HTTP transport (A3 pattern) — this exercises
/// BOTH the screen state machine and the provider/network contract.
void main() {
  final storage = SecureStorageMock();

  Job jobFixture() => Job(
        id: 'job-r1',
        ownerId: 'owner-1',
        employeeId: 'emp-9',
        userId: 'cust-1',
        serviceId: 'svc-1',
        status: 'completed',
        location: JobLocation(latitude: 30.0, longitude: 31.0),
        paymentMethod: 'cod',
      );

  // Inside testWidgets' FakeAsync zone, raw Future.delayed(Duration.zero)
  // timers never fire — drain frames/microtasks via tester.pump() instead.
  Future<void> settle(WidgetTester tester, [int turns = 8]) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump();
    }
  }

  void useMobileSurface(WidgetTester tester) {
    // Screen is designed for mobile width (isWide=false below 600dp) and the
    // star row fits exactly there; the 800x600 test default trips RenderFlex
    // overflow assertions that blank the subtree.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Pumps a localized app whose home button pushes RatingScreen, so success
  /// flows can be verified via an actual Navigator.pop.
  Future<MockHttpOverrides> pumpRatingScreen(
    WidgetTester tester,
    Job job, {
    Map<String, String> session = const {},
    required MockHttpHandler handler,
  }) async {
    storage.reset();
    storage.install();
    storage.store.addAll(session);
    useMobileSurface(tester);
    final overrides = installMockHttp(handler);
    final api = ApiClient(baseUrl: 'https://ci.local/api/v1');
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider<MarketplaceProvider>(
            create: (_) => MarketplaceProvider(api)),
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
        home: Scaffold(
          body: Builder(
            builder: (context) => const Center(
              child: Text('HOME-MARKER',
                  key: Key('home_marker'), style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
    ));

    // Navigate by pushing directly onto the root navigator.
    final navigator =
        Navigator.of(tester.element(find.byKey(const Key('home_marker'))));
    // Wait out AuthProvider auto-login so party determination sees the real
    // session (initState reads it once; a hydration race leaves placeholders).
    final authContext = tester.element(find.byKey(const Key('home_marker')));
    var guard = 0;
    while (session.isNotEmpty &&
        Provider.of<AuthProvider>(authContext, listen: false).user == null &&
        guard++ < 60) {
      await tester.pump();
    }
    unawaited(navigator
        .push(MaterialPageRoute(builder: (_) => RatingScreen(job: job))));
    // Zero-duration pump() calls do not advance route transitions.
    await tester.pumpAndSettle();
    return overrides;
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    // CTA sits below the fold on a 360x800 surface once info cards render.
    await tester.scrollUntilVisible(
      find.text('SUBMIT RATING'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('SUBMIT RATING'));
    await tester.pump();
    await tester.pump();
  }

  const customerSession = {
    'jwt_token': 'cust-tok',
    'user_id': 'cust-1',
    'user_email': 'c@x.dev',
    'user_role': 'customer',
  };

  testWidgets('customer rates the employee: party labels + waiting state',
      (tester) async {
    await pumpRatingScreen(
      tester,
      jobFixture(),
      session: customerSession,
      handler: (req) {
        expect(req.uri.path, endsWith('/users/ratings'));
        expect(req.uri.queryParameters['user_id'], 'cust-tok');
        return MockHttpResponse(200, jsonBody: {'ratings': []});
      },
    );

    // Party determination: customer rates the assigned employee. The label
    // pair renders twice (profile card + form row).
    expect(find.text('Driver / Employee'), findsNWidgets(2));
    expect(find.text('Specialist'), findsOneWidget); // form row only
    // No other-party rating yet -> waiting visualizer, not locked-in.
    expect(find.text('Waiting for other party...'), findsOneWidget);
    expect(find.text('Feedback Locked In!'), findsNothing);
    // Default selection: all five stars filled.
    expect(find.text('Waiting for other party...'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    expect(find.byIcon(Icons.star_border), findsNothing);
    // Localized CTA from ARB key ratingSubmitBtn.
    expect(find.text('SUBMIT RATING'), findsOneWidget);
  });

  testWidgets('other-party-already-rated branch shows the locked-in state',
      (tester) async {
    await pumpRatingScreen(
      tester,
      jobFixture(),
      session: customerSession,
      handler: (req) => MockHttpResponse(200, jsonBody: {
        'ratings': [
          {'job_id': 'other-job', 'rated_by': 'emp-9'},
          {'job_id': 'job-r1', 'rated_by': 'emp-9'},
        ],
      }),
    );
    await settle(tester);

    expect(find.text('Feedback Locked In!'), findsOneWidget);
    expect(find.text('Waiting for other party...'), findsNothing);
  });

  testWidgets('submit posts the trimmed blind-rating payload and pops',
      (tester) async {
    final overrides = await pumpRatingScreen(
      tester,
      jobFixture(),
      session: customerSession,
      handler: (req) {
        if (req.uri.path.endsWith('/users/jobs/rate')) {
          return MockHttpResponse(200, jsonBody: {'ok': true});
        }
        return MockHttpResponse(200, jsonBody: {'ratings': []});
      },
    );

    await tester.enterText(
        find.byType(TextField).first, '  great delivery, careful driver  ');
    // Select 4 stars: tapping the first star icon sets _selectedStars = 1.
    await tester.tap(find.byIcon(Icons.star).first);
    await tester.pump();
    expect(find.byIcon(Icons.star_border), findsNWidgets(4));

    await tapSubmit(tester);

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/rate'));
    expect(jsonDecode(posted.body!), {
      'job_id': 'job-r1',
      'rated_by': 'cust-tok',
      'rated_user': 'emp-9',
      'stars': 1,
      'comment': 'great delivery, careful driver',
    });
    // Success snackbar renders, then automatic pop back to the home marker.
    expect(find.text('Blind rating submitted successfully!'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(RatingScreen), findsNothing);
    expect(find.byKey(const Key('home_marker')), findsOneWidget);
  });

  testWidgets('submit failure surfaces the error snackbar and stays on screen',
      (tester) async {
    await pumpRatingScreen(
      tester,
      jobFixture(),
      session: customerSession,
      handler: (req) {
        if (req.uri.path.endsWith('/users/jobs/rate')) {
          return MockHttpResponse(500, jsonBody: {'error': 'db down'});
        }
        return MockHttpResponse(200, jsonBody: {'ratings': []});
      },
    );

    await tapSubmit(tester);

    expect(find.textContaining('(status: 500)'), findsOneWidget);
    expect(find.byType(RatingScreen), findsOneWidget);
    // Expire the snackbar timer so no fake-async timer leaks at teardown.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('employee rates the owner instead (party inversion)',
      (tester) async {
    final overrides = await pumpRatingScreen(
      tester,
      jobFixture(),
      session: {
        'jwt_token': 'emp-tok',
        'user_id': 'emp-9',
        'user_email': 'e@x.dev',
        'user_role': 'employee',
      },
      handler: (req) {
        if (req.uri.path.endsWith('/auth/user')) {
          return MockHttpResponse(200, jsonBody: {
            'id': 'emp-9',
            'email': 'e@x.dev',
            'username': 'nine',
            'role': 'employee',
          });
        }
        if (req.uri.path.endsWith('/users/jobs/rate')) {
          return MockHttpResponse(200, jsonBody: {'ok': true});
        }
        return MockHttpResponse(200, jsonBody: {'ratings': []});
      },
    );
    await settle(tester);

    expect(find.text('Client / Owner'), findsNWidgets(2));
    expect(find.text('Owner'), findsOneWidget); // subtitle, single site

    await tester.dragUntilVisible(find.text('SUBMIT RATING'),
        find.byType(SingleChildScrollView), const Offset(0, -200));
    await tester.tap(find.text('SUBMIT RATING'));
    await tester.pump();
    await tester.pump();

    final posted = overrides.requests
        .lastWhere((r) => r.uri.path.endsWith('/users/jobs/rate'));
    final body = jsonDecode(posted.body!) as Map<String, dynamic>;
    expect(body['rated_by'], 'emp-tok');
    expect(body['rated_user'], 'owner-1'); // inverted target
  });

  testWidgets('identity guard blocks submit without any network call',
      (tester) async {
    final overrides = await pumpRatingScreen(
      tester,
      jobFixture(),
      session: const {}, // no auth user -> _otherPartyId stays null
      handler: (req) => MockHttpResponse.ok(),
    );
    await settle(tester);

    await tester.tap(find.text('SUBMIT RATING'));
    await settle(tester);

    expect(find.textContaining('Cannot determine other party identity.'),
        findsOneWidget);
    expect(
        overrides.requests
            .where((r) => r.uri.path.endsWith('/users/jobs/rate')),
        isEmpty);
  });
}
