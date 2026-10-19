import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_progress.dart';
import 'package:frontend/ui/components/qd_route_lines.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

void main() {
  group('QdRouteLines', () {
    for (final locale in bothLocales) {
      testWidgets('ring for pickup, square for drop-off [$locale]',
          (tester) async {
        await tester.pumpWidget(qdApp(
            const QdRouteLines(pickup: 'Next to the kiosk', dropoff: 'Gate 3'),
            locale: locale));
        expect(find.text('Next to the kiosk'), findsOneWidget);
        expect(find.text('Gate 3'), findsOneWidget);
        final marks = tester
            .widgetList<Container>(find.byWidgetPredicate((w) =>
                w is Container &&
                w.constraints?.maxWidth == 12 &&
                w.constraints?.maxHeight == 12))
            .map((c) => c.decoration! as BoxDecoration)
            .toList();
        expect(marks[0].shape, BoxShape.circle);
        expect(marks[1].shape, BoxShape.rectangle);
        expect(marks[1].color, QdColors.light.gold);
        // Pickup above drop-off.
        expect(tester.getTopLeft(find.text('Next to the kiosk')).dy,
            lessThan(tester.getTopLeft(find.text('Gate 3')).dy));
      });
    }

    testWidgets('captions default to pickup / drop-off, announced together',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          qdApp(const QdRouteLines(pickup: 'A', dropoff: 'B'), locale: en));
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Drop-off'), findsOneWidget);
      expect(find.bySemanticsLabel('Pickup: A'), findsOneWidget);
      expect(find.bySemanticsLabel('Drop-off: B'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('compact form has no captions and one line each',
        (tester) async {
      await tester.pumpWidget(
          qdApp(const QdRouteLines(pickup: 'A', dropoff: 'B', compact: true)));
      expect(find.text('الاستلام'), findsNothing);
      expect(tester.widget<Text>(find.text('A')).maxLines, 1);
    });
  });

  group('QdStepProgress', () {
    testWidgets('fills segments up to current, announces the step',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          qdApp(const QdStepProgress(total: 4, current: 2), locale: en));
      final colors = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(QdStepProgress),
              matching: find.byType(Container)))
          .map((c) => (c.decoration! as BoxDecoration).color)
          .toList();
      final n = QdColors.light.navy, e = QdColors.light.border;
      expect(colors, [n, n, n, e]);
      expect(find.bySemanticsLabel('Step 3 of 4'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('out-of-range current is clamped', (tester) async {
      await tester
          .pumpWidget(qdApp(const QdStepProgress(total: 3, current: 9)));
      expect(tester.takeException(), isNull);
    });
  });

  group('QdTimeline', () {
    const steps = [
      QdTimelineStep(
          label: 'Ordered', state: QdTimelineState.done, time: '2:10 PM'),
      QdTimelineStep(label: 'Accepted', state: QdTimelineState.done),
      QdTimelineStep(
          label: 'On the way', state: QdTimelineState.current, time: 'Now'),
      QdTimelineStep(label: 'Delivered', state: QdTimelineState.upcoming),
    ];

    for (final locale in bothLocales) {
      testWidgets('done / current / upcoming styles [$locale]', (tester) async {
        await tester
            .pumpWidget(qdApp(const QdTimeline(steps: steps), locale: locale));
        expect(tester.widget<Text>(find.text('On the way')).style?.fontWeight,
            FontWeight.w700);
        expect(tester.widget<Text>(find.text('Delivered')).style?.color,
            QdColors.light.textSecondary);
        expect(find.text('2:10 PM'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('each row announces label, state and time', (tester) async {
      final handle = tester.ensureSemantics();
      await tester
          .pumpWidget(qdApp(const QdTimeline(steps: steps), locale: en));
      expect(find.bySemanticsLabel('Ordered, Done, 2:10 PM'), findsOneWidget);
      expect(find.bySemanticsLabel('On the way, Current step, Now'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Delivered, Not yet'), findsOneWidget);
      handle.dispose();
    });
  });
}
