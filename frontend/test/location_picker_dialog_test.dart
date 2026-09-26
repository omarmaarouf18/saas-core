import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:frontend/widgets/location_picker_dialog.dart';
import 'package:frontend/widgets/location_picker_map.dart';
import 'package:frontend/widgets/primary_button.dart';

class _MockGeolocatorPlatform extends GeolocatorPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      Position(
        latitude: 30.0,
        longitude: 31.0,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}

Widget _dialogHarness({
  Key? dialogKey,
  String title = 'Pick a location',
  Key? confirmButtonKey,
  IconData? confirmTrailingIcon,
  required ValueChanged<LatLng> onConfirmed,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: quickDeliveryTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open_picker_button'),
            onPressed: () => LocationPickerDialog.show(
              context,
              dialogKey: dialogKey,
              title: title,
              initialLocation: const LatLng(30.0444, 31.2357),
              confirmLabel: 'Confirm pin',
              confirmButtonKey: confirmButtonKey,
              confirmTrailingIcon: confirmTrailingIcon,
              onConfirmed: onConfirmed,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    GeolocatorPlatform.instance = _MockGeolocatorPlatform();
  });

  testWidgets('renders shared chrome with caller copy and keys',
      (WidgetTester tester) async {
    LatLng? confirmed;
    await tester.pumpWidget(_dialogHarness(
      dialogKey: const Key('test_picker_dialog'),
      title: 'Pick a location',
      confirmButtonKey: const Key('test_confirm_btn'),
      onConfirmed: (picked) => confirmed = picked,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_picker_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('test_picker_dialog')), findsOneWidget);
    expect(find.text('Pick a location'), findsOneWidget);
    expect(find.byType(LocationPickerMap), findsOneWidget);
    expect(find.byKey(const Key('test_confirm_btn')), findsOneWidget);
    expect(confirmed, isNull);
  });

  testWidgets('confirm fires the selection and pops the dialog',
      (WidgetTester tester) async {
    LatLng? confirmed;
    await tester.pumpWidget(_dialogHarness(
      confirmButtonKey: const Key('test_confirm_btn'),
      onConfirmed: (picked) => confirmed = picked,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_picker_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('test_confirm_btn')));
    await tester.pumpAndSettle();

    // Default selection is the initial location (no map interaction).
    expect(confirmed, const LatLng(30.0444, 31.2357));
    expect(find.byType(LocationPickerDialog), findsNothing);
  });

  testWidgets('close pops without firing the callback',
      (WidgetTester tester) async {
    var calls = 0;
    await tester.pumpWidget(_dialogHarness(
      onConfirmed: (_) => calls++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_picker_button')));
    await tester.pumpAndSettle();
    expect(find.byType(LocationPickerDialog), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.byType(LocationPickerDialog), findsNothing);
  });

  testWidgets('confirm trailing icon renders when provided',
      (WidgetTester tester) async {
    await tester.pumpWidget(_dialogHarness(
      confirmTrailingIcon: Icons.arrow_forward,
      onConfirmed: (_) {},
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_picker_button')));
    await tester.pumpAndSettle();

    final confirmBtn = find.descendant(
      of: find.byType(PrimaryButton),
      matching: find.byIcon(Icons.arrow_forward),
    );
    expect(confirmBtn, findsOneWidget);
  });
}
