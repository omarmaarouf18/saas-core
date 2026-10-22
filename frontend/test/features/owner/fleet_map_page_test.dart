import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/fleet_map_page.dart';
import 'package:frontend/features/owner/owner_rules.dart';

import 'owner_harness.dart';

void main() {
  group('fleet rules', () {
    final jobs = [
      ownerJob(id: 'job-live', status: 'active'),
      ownerJob(id: 'job-done', status: 'completed'),
    ];

    test('a known finished job counts as free, an unknown one is trusted', () {
      expect(fleetJobIdOf('job-live', jobs), 'job-live');
      expect(fleetJobIdOf('job-done', jobs), isNull);
      expect(fleetJobIdOf('job-older', jobs), 'job-older');
      expect(fleetJobIdOf(null, jobs), isNull);
      expect(fleetJobIdOf('', jobs), isNull);
    });

    test('filters', () {
      expect(fleetFilterMatches(FleetFilter.all, null), isTrue);
      expect(fleetFilterMatches(FleetFilter.onJob, 'j'), isTrue);
      expect(fleetFilterMatches(FleetFilter.onJob, null), isFalse);
      expect(fleetFilterMatches(FleetFilter.free, null), isTrue);
      expect(fleetFilterMatches(FleetFilter.free, 'j'), isFalse);
    });
  });

  group('OwnerFleetMapPage', () {
    OwnerTestDeps fleetDeps() {
      final deps = OwnerTestDeps();
      deps.owner.nextEmployees = [
        staff('emp-1', 'Karim'),
        staff('emp-2', 'Sara'),
      ];
      deps.owner.nextJobs = [
        ownerJob(id: 'b7c1d2e3f4a5', employeeId: 'emp-1'),
      ];
      deps.map.nextMarkers = [
        courierAt('emp-1', jobId: 'b7c1d2e3f4a5'),
        courierAt('emp-2', lat: 30.06, lon: 31.25),
      ];
      return deps;
    }

    Future<void> pumpMap(WidgetTester tester, OwnerTestDeps deps,
        {String? focus}) async {
      await pumpOwner(tester, deps, OwnerFleetMapPage(focusEmployeeId: focus));
    }

    testWidgets('hydrates, subscribes to fleet:<ownerId>, names from roster',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps);

      expect(deps.map.hydrateCalls, ['owner-jwt']);
      expect(deps.map.subscribeCalls, ['fleet:owner-1']);
      expect(deps.map.names, {'emp-1': 'Karim', 'emp-2': 'Sara'});
      expect(find.byKey(const Key('own_fleet_marker_emp-1')), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_marker_emp-2')), findsOneWidget);
      expect(find.text('On the map: 2 · on a job: 1'), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_reconnecting')), findsNothing);
    });

    testWidgets('the socket is torn down when the page closes',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(deps.map.disconnects, 1);
    });

    testWidgets('loads the roster when the shell has not yet', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await tester.pumpWidget(ownerApp(deps, const OwnerFleetMapPage()));
      await tester.pumpAndSettle();
      expect(deps.owner.employeeCalls, 1);
    });

    testWidgets('filters: on a job / free', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps);

      await tester.tap(find.byKey(const Key('own_fleet_filter_onJob')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_fleet_marker_emp-1')), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_marker_emp-2')), findsNothing);

      await tester.tap(find.byKey(const Key('own_fleet_filter_free')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_fleet_marker_emp-1')), findsNothing);
      expect(find.byKey(const Key('own_fleet_marker_emp-2')), findsOneWidget);
    });

    testWidgets('a courier who just delivered counts as free', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.owner.nextJobs = [
        ownerJob(id: 'b7c1d2e3f4a5', employeeId: 'emp-1', status: 'completed'),
      ];
      await pumpMap(tester, deps);
      expect(find.text('On the map: 2 · on a job: 0'), findsOneWidget);
    });

    testWidgets('selected courier: sheet with order and courier page',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps);
      await tester.tap(find.byKey(const Key('own_fleet_marker_emp-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('own_fleet_sheet_emp-1')), findsOneWidget);
      expect(find.text('Karim'), findsOneWidget);
      expect(find.text('Last update 3 min ago'), findsOneWidget);
      expect(
          find.text(
              'Order \u2066#QD-B7C1D2E3\u2069 · to Zamalek, 26th of July St'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('own_fleet_sheet_order')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_order_page')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('own_fleet_sheet_courier')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_employee_page')), findsOneWidget);
    });

    testWidgets('a free courier has no order row; close returns the summary',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps, focus: 'emp-2');
      expect(find.byKey(const Key('own_fleet_sheet_emp-2')), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_sheet_order')), findsNothing);
      await tester.tap(find.byKey(const Key('own_fleet_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_fleet_summary')), findsOneWidget);
    });

    testWidgets('reconnect banner while the socket is down', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.map.isConnected = false;
      await pumpMap(tester, deps);
      expect(find.byKey(const Key('own_fleet_reconnecting')), findsOneWidget);
      expect(find.text('Reconnecting to live locations…'), findsOneWidget);

      deps.map.isConnected = true;
      deps.map.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('own_fleet_reconnecting')), findsNothing);
    });

    testWidgets('forbidden channel: access banner, not reconnecting',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.map
        ..subscriptionError = 'forbidden'
        ..isConnected = false;
      await pumpMap(tester, deps);
      expect(find.byKey(const Key('own_fleet_denied')), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_reconnecting')), findsNothing);
      expect(find.text('forbidden'), findsNothing);
    });

    testWidgets('load error: localized banner and retry', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.map
        ..nextMarkers = null
        ..nextError = 'SocketException: raw text';
      await pumpMap(tester, deps);
      expect(find.byKey(const Key('own_fleet_error')), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);

      deps.map
        ..nextError = null
        ..nextMarkers = [courierAt('emp-2')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(deps.map.hydrateCalls, hasLength(2));
      expect(find.byKey(const Key('own_fleet_error')), findsNothing);
      expect(find.byKey(const Key('own_fleet_marker_emp-2')), findsOneWidget);
    });

    testWidgets('nobody sharing: notice with refresh', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.map.nextMarkers = [];
      await pumpMap(tester, deps);
      expect(find.byKey(const Key('own_fleet_empty')), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(deps.map.hydrateCalls, hasLength(2));
    });

    testWidgets('loading spinner until the first markers arrive',
        (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      await pumpMap(tester, deps);
      deps.map
        ..markersList = []
        ..isLoading = true;
      deps.map.notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('own_fleet_loading')), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_empty')), findsNothing);
    });

    testWidgets('unknown courier id falls back to a short id', (tester) async {
      usePhone(tester);
      final deps = fleetDeps();
      deps.map.nextMarkers = [courierAt('emp-zz9999')];
      await pumpMap(tester, deps, focus: 'emp-zz9999');
      expect(find.textContaining('emp-zz'), findsOneWidget);
      expect(find.byKey(const Key('own_fleet_sheet_courier')), findsNothing);
    });
  });
}
