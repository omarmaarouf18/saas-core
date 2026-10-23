import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/courier/task_page.dart';
import 'package:frontend/models/job.dart';

import 'courier_harness.dart';

// FE-V2-CONSUME item 5: offer and current job show the address text first,
// then the landmark note, then "Pinned location"; package size and notes.

Future<void> _pump(WidgetTester tester, Job job) async {
  usePhone(tester);
  final d = CourierTestDeps();
  d.jobs.seed([job]);
  await pumpCourier(tester, d, const CourierTaskPage());
  await tester.pumpAndSettle();
}

/// The texts of a stop, in reading order.
List<String> _stopTexts(WidgetTester tester, String key) => [
      for (final t in tester.widgetList<Text>(find.descendant(
          of: find.byKey(Key(key)), matching: find.byType(Text))))
        t.data ?? '',
    ];

void main() {
  for (final (status, sub) in [
    ('pending_dispatch', null),
    ('active', 'picked_up'),
  ]) {
    testWidgets('$status: address, then note, then pinned', (tester) async {
      await _pump(
          tester,
          courierJob(
            status: status,
            subStatus: sub,
            offerExpiresAt: courierNow.add(const Duration(seconds: 40)),
            pickupAddress: '15 Qasr El Nil St',
            pickupNote: 'Floor 3',
            dropAddress: null,
            dropNote: null,
            package: const JobPackageDetails(size: 'large', notes: 'Glass'),
          ));
      final pickup = _stopTexts(tester, 'courier_stop_pickup');
      expect(pickup.sublist(1), ['15 Qasr El Nil St', 'Floor 3']);
      final drop = _stopTexts(tester, 'courier_stop_dropoff');
      expect(drop.sublist(1), ['Pinned location']);
      expect(find.text('Package: Large · Glass'), findsOneWidget);
    });
  }

  testWidgets('note only: the note is the title', (tester) async {
    await _pump(
        tester,
        courierJob(
            subStatus: 'heading_to_pickup',
            pickupAddress: null,
            pickupNote: 'Beside the kiosk'));
    expect(_stopTexts(tester, 'courier_stop_pickup').sublist(1),
        ['Beside the kiosk']);
  });

  testWidgets('package notes only', (tester) async {
    await _pump(
        tester,
        courierJob(
            subStatus: 'picked_up',
            package: const JobPackageDetails(notes: 'Keep upright')));
    expect(find.text('Package: Keep upright'), findsOneWidget);
  });
}
