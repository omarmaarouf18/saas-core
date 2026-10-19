import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_bottom_nav.dart';
import 'package:frontend/ui/components/qd_segmented.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

const _items = [
  QdNavItem(icon: Icons.home_outlined, label: 'Home'),
  QdNavItem(icon: Icons.receipt_long_outlined, label: 'My orders'),
  QdNavItem(icon: Icons.person_outline, label: 'Account'),
];

List<Container> _indicators(WidgetTester tester) => tester
    .widgetList<Container>(find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 20 &&
        w.constraints?.maxHeight == 3))
    .toList();

void main() {
  group('QdSegmented', () {
    for (final locale in bothLocales) {
      testWidgets('selects and reports changes [$locale]', (tester) async {
        var selected = 0;
        await tester.pumpWidget(StatefulBuilder(
          builder: (context, setState) => qdApp(
            QdSegmented<int>(
              segments: const [
                QdSegment(value: 0, label: 'Current'),
                QdSegment(value: 1, label: 'Past'),
              ],
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
            locale: locale,
          ),
        ));
        await tester.tap(find.text('Past'));
        await tester.pump();
        expect(selected, 1);
        expect(tester.widget<Text>(find.text('Past')).style?.fontWeight,
            FontWeight.w600);
        expect(tester.getSize(find.byType(QdSegmented<int>)).height,
            greaterThanOrEqualTo(48));
      });
    }

    testWidgets('long labels scale down on one line, never wrap',
        (tester) async {
      await tester.pumpWidget(qdApp(SizedBox(
        width: 240,
        child: QdSegmented<int>(
          segments: const [
            QdSegment(value: 0, label: 'All couriers 12'),
            QdSegment(value: 1, label: 'Working right now'),
            QdSegment(value: 2, label: 'Frozen accounts'),
          ],
          selected: 0,
          onChanged: (_) {},
        ),
      )));
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.maxLines, 1);
        expect(t.softWrap, isFalse);
      }
      expect(find.byType(FittedBox), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('semantics mark the selected tab', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(qdApp(QdSegmented<int>(
        segments: const [
          QdSegment(value: 0, label: 'Current'),
          QdSegment(value: 1, label: 'Past'),
        ],
        selected: 0,
        onChanged: (_) {},
      )));
      expect(
          tester.getSemantics(find.bySemanticsLabel('Current')),
          matchesSemantics(
            label: 'Current',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true,
          ));
      handle.dispose();
    });

    test('rejects 1 or 4 options', () {
      expect(
          () => QdSegmented<int>(
              segments: const [QdSegment(value: 0, label: 'a')],
              selected: 0,
              onChanged: (_) {}),
          throwsAssertionError);
    });
  });

  group('QdBottomNav', () {
    for (final locale in bothLocales) {
      testWidgets('gold indicator under the active item only [$locale]',
          (tester) async {
        var index = 0;
        await tester.pumpWidget(StatefulBuilder(
          builder: (context, setState) => qdApp(
            QdBottomNav(
              items: _items,
              currentIndex: index,
              onTap: (i) => setState(() => index = i),
            ),
            locale: locale,
          ),
        ));
        await tester.tap(find.text('My orders'));
        await tester.pump();
        expect(index, 1);
        final colors = _indicators(tester)
            .map((c) => (c.decoration! as BoxDecoration).color)
            .toList();
        expect(colors, [
          Colors.transparent,
          QdColors.light.gold,
          Colors.transparent,
        ]);
        expect(tester.widget<Text>(find.text('My orders')).style?.color,
            QdColors.light.textPrimary);
        expect(tester.widget<Text>(find.text('Home')).style?.color,
            QdColors.light.textSecondary);
      });
    }

    testWidgets('semantics: labelled, selected item marked', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(qdApp(
          QdBottomNav(items: _items, currentIndex: 2, onTap: (_) {}),
          locale: en));
      expect(find.bySemanticsLabel('Main navigation'), findsOneWidget);
      expect(
          tester.getSemantics(find.bySemanticsLabel('Account')),
          matchesSemantics(
            label: 'Account',
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            hasTapAction: true,
          ));
      for (final label in ['Home', 'My orders', 'Account']) {
        expect(tester.getSize(find.bySemanticsLabel(label)).height,
            greaterThanOrEqualTo(48));
      }
      handle.dispose();
    });

    test('takes 3 or 4 items', () {
      expect(
          () => QdBottomNav(
              items: _items.take(2).toList(), currentIndex: 0, onTap: (_) {}),
          throwsAssertionError);
    });
  });
}
