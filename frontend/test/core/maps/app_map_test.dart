import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/maps/app_map.dart';
import 'package:frontend/core/maps/map_marker_renderer.dart';
import 'package:frontend/core/maps/waddify_map_style.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/qd_ui.dart';

import '../../helpers/fake_app_map.dart';

Widget _wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: qdLightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SizedBox(width: 360, height: 300, child: child)),
    );

void main() {
  test('Waddify map style JSONs parse cleanly', () {
    final light = jsonDecode(waddifyLightMapStyle);
    final dark = jsonDecode(waddifyDarkMapStyle);
    expect(light, isA<List<dynamic>>());
    expect(dark, isA<List<dynamic>>());
    expect((light as List).isNotEmpty, isTrue);
    expect((dark as List).isNotEmpty, isTrue);
  });

  test('marker PNG renderer produces valid PNG bytes for every kind', () async {
    for (final icon in [
      const AppMarkerIcon.pickupRing(),
      const AppMarkerIcon.dropoffSquare(),
      const AppMarkerIcon.selfDot(),
      const AppMarkerIcon.courierPin(),
      AppMarkerIcon.fleetCourier(initial: 'K', onJob: true, selected: true),
      AppMarkerIcon.fleetCourier(initial: 'S', onJob: false, selected: false),
    ]) {
      final png = await renderAppMarkerPng(icon, QdColors.light);
      // PNG magic bytes: 89 50 4E 47
      expect(png.length, greaterThan(20));
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
  });

  testWidgets('missing API key renders map unavailable state in EN and AR',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const AppMap(
        initialCenter: AppLatLng(30.0444, 31.2357),
        hasApiKey: false,
      ),
    ));
    expect(find.byKey(const Key('app_map_unavailable')), findsOneWidget);
    expect(find.text('Map unavailable'), findsOneWidget);

    await tester.pumpWidget(_wrap(
      const AppMap(
        initialCenter: AppLatLng(30.0444, 31.2357),
        hasApiKey: false,
      ),
      locale: const Locale('ar'),
    ));
    expect(find.byKey(const Key('app_map_unavailable')), findsOneWidget);
    expect(find.text('الخريطة مش متاحة دلوقتي'), findsOneWidget);
  });

  testWidgets(
      'AppMap renders fake via AppMapScope: markers, polyline, camera move, fitBounds, idle and tap',
      (tester) async {
    final controller = AppMapController();
    final idleCenters = <AppLatLng>[];
    final taps = <AppLatLng>[];
    var markerTapped = false;
    var readyCalls = 0;

    await tester.pumpWidget(_wrap(
      AppMapScope(
        hasApiKey: true,
        builder: fakeAppMapBuilder,
        child: AppMap(
          initialCenter: const AppLatLng(30.0444, 31.2357),
          initialZoom: 14,
          controller: controller,
          semanticLabel: 'Test map',
          markers: [
            AppMapMarker(
              id: 'pickup',
              markerKey: const Key('test_marker_pickup'),
              position: const AppLatLng(30.0444, 31.2357),
              icon: const AppMarkerIcon.pickupRing(),
              onTap: () => markerTapped = true,
            ),
          ],
          polylines: [
            AppMapPolyline(
              id: 'route',
              points: const [
                AppLatLng(30.0444, 31.2357),
                AppLatLng(30.0600, 31.2200),
              ],
              color: QdColors.light.navy,
            ),
          ],
          onMapReady: () => readyCalls++,
          onCameraIdle: idleCenters.add,
          onTap: taps.add,
        ),
      ),
    ));
    await tester.pump();

    expect(readyCalls, 1);
    expect(controller.isReady, isTrue);
    expect(find.byKey(const Key('test_marker_pickup')), findsOneWidget);

    // Marker tap callback fires.
    await tester.tap(find.byKey(const Key('test_marker_pickup')));
    expect(markerTapped, isTrue);

    // Map tap callback fires with unprojected coordinate.
    await tester.tapAt(const Offset(100, 100));
    expect(taps, hasLength(1));

    // Drag moves camera and triggers onCameraIdle with the new centre.
    await tester.drag(find.byType(AppMap), const Offset(-100, 80));
    await tester.pump();
    expect(idleCenters, isNotEmpty);
    expect(idleCenters.last.latitude, isNot(closeTo(30.0444, 1e-5)));

    // Programmatic move + zoomBy + fitBounds update camera and trigger idle.
    controller.move(const AppLatLng(30.1, 31.3), zoom: 16);
    await tester.pump();
    expect(controller.center, const AppLatLng(30.1, 31.3));
    expect(controller.zoom, 16);

    controller.zoomBy(-2);
    await tester.pump();
    expect(controller.zoom, 14);

    controller.fitBounds(const [
      AppLatLng(30.0, 31.0),
      AppLatLng(30.1, 31.1),
    ]);
    await tester.pump();
    expect(controller.center!.latitude, closeTo(30.05, 0.01));
    expect(controller.center!.longitude, closeTo(31.05, 0.01));
  });
}
