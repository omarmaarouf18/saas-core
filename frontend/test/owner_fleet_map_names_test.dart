import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/employee_marker.dart';
import 'package:frontend/providers/map_tracking_provider.dart';
import 'package:frontend/providers/owner_provider.dart';
import 'package:frontend/screens/owner_fleet_map_screen.dart';

class _MockOwner extends OwnerProvider {
  final List<dynamic> mockEmployees;
  _MockOwner(super.apiClient, {this.mockEmployees = const []});

  @override
  List<dynamic> get employees => mockEmployees;

  @override
  Future<List<dynamic>> fetchEmployees([String? ownerToken]) async =>
      mockEmployees;
}

const _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

Widget _fleetApp({
  required MapTrackingProvider mapProvider,
  OwnerProvider? ownerProvider,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: _delegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<MapTrackingProvider>.value(value: mapProvider),
        if (ownerProvider != null)
          ChangeNotifierProvider<OwnerProvider>.value(value: ownerProvider),
      ],
      child: const OwnerFleetMapScreen(ownerId: 'owner-1'),
    ),
  );
}

EmployeeMarkerData _marker(String employeeId, {String? jobId}) =>
    EmployeeMarkerData(
      employeeId: employeeId,
      jobId: jobId,
      latitude: 30.0444,
      longitude: 31.2357,
      updatedAt: DateTime(2026, 9, 1, 8, 0, 0),
    );

void main() {
  group('Fleet map employee names', () {
    testWidgets('Marker and card render the resolved roster username',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final mapProvider = MapTrackingProvider(apiClient);
      final ownerProvider = _MockOwner(apiClient, mockEmployees: [
        {'id': 'emp-9', 'username': 'Ziad Courier'},
      ]);
      mapProvider.updateMarkerManually(_marker('emp-9', jobId: 'job-1'));
      mapProvider.setEmployeeNameLookup({'emp-9': 'Ziad Courier'});

      await tester.pumpWidget(
          _fleetApp(mapProvider: mapProvider, ownerProvider: ownerProvider));
      await tester.pumpAndSettle();

      // Pin label shows the name, never the raw ID.
      expect(find.text('Ziad Courier'), findsOneWidget);
      expect(find.text('emp-9'), findsNothing);
      expect(find.textContaining('Unknown'), findsNothing);

      // Open the driver card by tapping the pin label.
      await tester.tap(find.text('Ziad Courier'));
      await tester.pumpAndSettle();

      // Card title repeats the name; avatar initial derives from the name.
      expect(find.text('Ziad Courier'), findsNWidgets(2));
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('Unmatched employee falls back to a distinct Unknown label',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final mapProvider = MapTrackingProvider(apiClient);
      final ownerProvider = _MockOwner(apiClient, mockEmployees: [
        {'id': 'emp-9', 'username': 'Ziad Courier'},
      ]);
      mapProvider.updateMarkerManually(_marker('stale-employee-999'));

      await tester.pumpWidget(
          _fleetApp(mapProvider: mapProvider, ownerProvider: ownerProvider));
      await tester.pumpAndSettle();

      // Truncated ID with an explicit Unknown prefix (existing statusUnknown
      // l10n convention) — diagnosable, not a bare ID, never "null".
      expect(find.text('Unknown: stale-employ'), findsOneWidget);
      expect(find.text('stale-employee-999'), findsNothing);

      await tester.tap(find.text('Unknown: stale-employ'));
      await tester.pumpAndSettle();

      // Avatar initials fall back to the ID-derived characters.
      expect(find.text('ST'), findsOneWidget);
    });

    testWidgets('Missing OwnerProvider renders the fallback without crashing',
        (WidgetTester tester) async {
      final apiClient = ApiClient();
      final mapProvider = MapTrackingProvider(apiClient);
      mapProvider.updateMarkerManually(_marker('emp-9', jobId: 'job-1'));

      await tester.pumpWidget(_fleetApp(mapProvider: mapProvider));
      await tester.pumpAndSettle();

      expect(find.text('Unknown: emp-9'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MapTrackingProvider name lookup', () {
    test('Backfills existing markers and applies to later updates', () async {
      final provider = MapTrackingProvider(ApiClient());
      provider.updateMarkerManually(_marker('emp-9'));

      provider.setEmployeeNameLookup({'emp-9': 'Ziad Courier'});
      expect(provider.markersList.single.employeeName, 'Ziad Courier');

      // Roster change clears names that no longer match.
      provider.setEmployeeNameLookup(const {});
      expect(provider.markersList.single.employeeName, isNull);

      // Lookup stored for markers created afterwards (live heartbeats).
      provider.setEmployeeNameLookup({'emp-9': 'Ziad Courier'});
      provider.handleIncomingDataForTest(
        '{"type":"location_update","employee_id":"emp-9","latitude":30.05,"longitude":31.24,"job_id":"job-2"}',
      );
      final updated = provider.markersList.single;
      expect(updated.employeeName, 'Ziad Courier');
      expect(updated.jobId, 'job-2');
    });
  });
}
