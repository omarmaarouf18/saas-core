import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/job.dart';
import 'package:frontend/widgets/job_location_mini_map.dart';
import 'package:frontend/widgets/route_timeline.dart';

void main() {
  final dest = JobLocation(latitude: 30.0444, longitude: 31.2357);

  testWidgets('mini map renders pin, tiles layer, and coords caption',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: JobLocationMiniMap(location: dest),
          ),
        ),
      ),
    );
    await tester.pump();

    // Same OSM stack as the rest of the app (tile layer present; tiles
    // 400-and-blank deterministically in tests).
    expect(find.byType(TileLayer), findsOneWidget);
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers, hasLength(1));
    expect(markerLayer.markers.first.point.latitude, 30.0444);
    expect(markerLayer.markers.first.point.longitude, 31.2357);
    // Exact numbers retained as a small caption (visual primary).
    expect(find.text(dest.formatCoordinates()), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('route timeline renders map slot instead of detail text',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteTimeline(
            pickupAddress: 'Pickup',
            pickupDetail: '29.9792, 31.1342',
            dropoffAddress: 'Dropoff',
            dropoffDetail: dest.formatCoordinates(),
            dropoffMap: JobLocationMiniMap(location: dest),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(JobLocationMiniMap), findsOneWidget);
    // The raw pair survives exactly once (the mini-map caption) — the
    // timeline detail-text branch is replaced, not duplicated.
    expect(find.text(dest.formatCoordinates()), findsOneWidget);
  });

  testWidgets('route timeline keeps legacy text branch without the slot',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteTimeline(
            pickupAddress: 'Pickup',
            dropoffAddress: 'Dropoff',
            dropoffDetail: dest.formatCoordinates(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(JobLocationMiniMap), findsNothing);
    expect(find.text(dest.formatCoordinates()), findsOneWidget);
  });
}
