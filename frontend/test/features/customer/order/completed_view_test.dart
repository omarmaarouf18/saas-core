import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/features/customer/order/rating_page.dart';

import '../customer_harness.dart';
import 'order_fixtures.dart';
import 'order_harness.dart';

void main() {
  final delivered =
      orderJob(status: 'completed', employeeId: 'emp-1', agreed: 45);

  Future<void> openRating(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('ord_rate')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerRatingPage), findsOneWidget);
  }

  testWidgets('completed: paid amount, route, rate button; no polling',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, delivered,
        lookup: FakeCourierLookup({'emp-1': 'Karim'}));
    expect(find.byKey(const Key('ord_view_completed')), findsOneWidget);
    expect(find.text('Your order was delivered'), findsOneWidget);
    expect(find.text('You paid EGP 45 cash'), findsOneWidget);
    expect(find.text('Paid cash'), findsOneWidget);
    expect(find.text('Rate Karim'), findsOneWidget);

    final calls = deps.marketplace.statusCalls.length;
    await tester.pump(const Duration(seconds: 30));
    expect(deps.marketplace.statusCalls.length, calls);
    await unmountOrder(tester, deps);
  });

  testWidgets('no courier: rates the company', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, orderJob(status: 'completed'));
    expect(find.text('Rate the company'), findsOneWidget);
    await openRating(tester);
    expect(find.text('How was the company?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate_send')));
    await tester.pumpAndSettle();
    expect(deps.marketplace.rateCalls.single['ratedUser'], 'tenant-svc-1');
    await unmountOrder(tester, deps);
  });

  testWidgets('rating: stars + trimmed comment, then the rated state',
      (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, delivered,
        lookup: FakeCourierLookup({'emp-1': 'Karim'}));
    await openRating(tester);

    expect(find.text('How was Karim?'), findsOneWidget);
    expect(find.byKey(const Key('rate_blind_note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('rate_star_4')));
    await tester.enterText(
        find.byKey(const Key('rate_comment')), '  Fast and polite  ');
    await tester.tap(find.byKey(const Key('rate_send')));
    await tester.pumpAndSettle();

    final call = deps.marketplace.rateCalls.single;
    expect(call['jobId'], 'a1b2c3d4e5f6');
    expect(call['ratedBy'], 'customer-jwt');
    expect(call['ratedUser'], 'emp-1');
    expect(call['stars'], 4);
    expect(call['comment'], 'Fast and polite');

    expect(find.byType(CustomerRatingPage), findsNothing);
    expect(find.byKey(const Key('ord_rated')), findsOneWidget);
    expect(find.byKey(const Key('ord_rate')), findsNothing);
    await unmountOrder(tester, deps);
  });

  testWidgets('five stars are preselected, like before', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, delivered);
    await openRating(tester);
    await tester.tap(find.byKey(const Key('rate_send')));
    await tester.pumpAndSettle();
    expect(deps.marketplace.rateCalls.single['stars'], 5);
    await unmountOrder(tester, deps);
  });

  for (final msg in ['already rated this job', 'Conflict']) {
    testWidgets('"$msg" from the server counts as success', (tester) async {
      final deps = CustomerTestDeps();
      deps.marketplace.nextRateError = ApiClientException(msg, statusCode: 409);
      await pumpOrder(tester, deps, delivered);
      await openRating(tester);
      await tester.tap(find.byKey(const Key('rate_send')));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerRatingPage), findsNothing);
      expect(find.byKey(const Key('ord_rated')), findsOneWidget);
      await unmountOrder(tester, deps);
    });
  }

  testWidgets('other failures stay on the page with a retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextRateError = apiError();
    await pumpOrder(tester, deps, delivered);
    await openRating(tester);
    await tester.tap(find.byKey(const Key('rate_send')));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerRatingPage), findsOneWidget);
    expect(
        find.textContaining("We couldn't send your rating."), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('"not now" returns without rating', (tester) async {
    final deps = CustomerTestDeps();
    await pumpOrder(tester, deps, delivered);
    await openRating(tester);
    await tester.tap(find.byKey(const Key('rate_not_now')));
    await tester.pumpAndSettle();
    expect(deps.marketplace.rateCalls, isEmpty);
    expect(find.byKey(const Key('ord_rate')), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('the other side already rated: says both are visible',
      (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.ratingsReceived = [
      {'job_id': 'other-job', 'rated_by': 'emp-1'},
      {'job_id': 'a1b2c3d4e5f6', 'rated_by': 'emp-1'},
    ];
    await pumpOrder(tester, deps, delivered);
    await openRating(tester);
    expect(find.byKey(const Key('rate_other_rated')), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  testWidgets('the other-side check failing has its own retry', (tester) async {
    final deps = CustomerTestDeps();
    deps.marketplace.nextRatingsError = apiError();
    await pumpOrder(tester, deps, delivered);
    await openRating(tester);
    expect(find.byKey(const Key('rate_other_failed')), findsOneWidget);

    deps.marketplace.nextRatingsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(deps.marketplace.ratingsCalls, 2);
    expect(find.byKey(const Key('rate_blind_note')), findsOneWidget);
    await unmountOrder(tester, deps);
  });

  test('ratedPartyOf: courier, else the owner, else nobody', () {
    expect(ratedPartyOf(orderJob(employeeId: 'emp-1')), 'emp-1');
    expect(ratedPartyOf(orderJob(employeeId: '  ')), 'tenant-svc-1');
    expect(ratedPartyOf(orderJob()), 'tenant-svc-1');
  });

  for (final locale in bothLocales) {
    testWidgets('rating page renders without overflow [${locale.languageCode}]',
        (tester) async {
      final deps = CustomerTestDeps();
      await pumpOrder(tester, deps, delivered, locale: locale);
      await tester.tap(find.byKey(const Key('ord_rate')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await unmountOrder(tester, deps);
    });
  }
}
