import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/qd_ui.dart';

import 'qd_harness.dart';

// FE-CUST-1 components: QdIconTile, QdIconButton, QdChoiceChips,
// QdRouteStops, QdPriceBreakdown, QdMapPin, QdMapLabel, QdDockedPanel,
// QdFooterBar.
void main() {
  group('QdIconTile', () {
    testWidgets('initial tile shows the first letter, blank name an icon',
        (tester) async {
      await tester.pumpWidget(qdApp(Row(children: [
        QdIconTile.initialOf('nile express'),
        QdIconTile.initialOf('   '),
      ])));
      expect(find.text('N'), findsOneWidget);
      expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    });

    testWidgets('tones use gold, muted and border fills', (tester) async {
      await tester.pumpWidget(qdApp(const Row(children: [
        QdIconTile(icon: Icons.add, tone: QdIconTileTone.gold),
        QdIconTile(icon: Icons.add),
        QdIconTile(icon: Icons.add, tone: QdIconTileTone.disabled),
      ])));
      final fills = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(QdIconTile), matching: find.byType(Container)))
          .map((c) => (c.decoration as BoxDecoration).color)
          .toList();
      expect(fills, [
        QdColors.light.gold,
        QdColors.light.fillMuted,
        QdColors.light.border,
      ]);
    });

    testWidgets('is decorative: no semantics of its own', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(qdApp(QdIconTile.initialOf('Nile')));
      expect(find.bySemanticsLabel('N'), findsNothing);
      handle.dispose();
    });
  });

  group('QdIconButton', () {
    for (final locale in bothLocales) {
      testWidgets('taps, 48dp target, badge in label [$locale]',
          (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await tester.pumpWidget(qdApp(
          QdIconButton(
            icon: Icons.notifications_none,
            label: 'Notifications',
            badgeCount: 3,
            onPressed: () => taps++,
          ),
          locale: locale,
        ));
        expect(tester.getSize(find.byType(QdIconButton)),
            const Size(QdSize.minTouch, QdSize.minTouch));
        expect(find.text('3'), findsOneWidget);
        expect(find.bySemanticsLabel('Notifications, 3'), findsOneWidget);
        await tester.tap(find.byType(QdIconButton));
        expect(taps, 1);
        handle.dispose();
      });
    }

    testWidgets('badge caps at 99+', (tester) async {
      await tester.pumpWidget(qdApp(QdIconButton(
          icon: Icons.add, label: 'x', badgeCount: 120, onPressed: () {})));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('loading and disabled ignore taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(qdApp(Row(children: [
        QdIconButton(
            key: const Key('loading'),
            icon: Icons.add,
            label: 'a',
            loading: true,
            onPressed: () => taps++),
        const QdIconButton(
            key: Key('disabled'), icon: Icons.add, label: 'b', onPressed: null),
      ])));
      await tester.tap(find.byKey(const Key('loading')));
      await tester.tap(find.byKey(const Key('disabled')));
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('QdChoiceChips', () {
    testWidgets('selected chip is navy, tapping another reports it',
        (tester) async {
      final handle = tester.ensureSemantics();
      int? picked;
      await tester.pumpWidget(qdApp(QdChoiceChips<int>(
        selected: 0,
        onChanged: (v) => picked = v,
        choices: const [
          QdChoice(value: 0, label: 'Nearest'),
          QdChoice(value: 1, label: 'Cheapest'),
        ],
      )));
      final selectedText = tester.widget<Text>(find.text('Nearest'));
      expect(selectedText.style?.color, QdColors.light.surface);
      expect(
          tester.getSemantics(find.text('Nearest')),
          matchesSemantics(
            label: 'Nearest',
            isButton: true,
            isSelected: true,
            isInMutuallyExclusiveGroup: true,
            hasSelectedState: true,
          ));
      await tester.tap(find.text('Nearest'));
      expect(picked, isNull);
      await tester.tap(find.text('Cheapest'));
      expect(picked, 1);
      expect(tester.getSize(find.byType(SizedBox).first).height,
          greaterThanOrEqualTo(QdSize.minTouch));
      handle.dispose();
    });
  });

  group('QdRouteStops', () {
    for (final locale in bothLocales) {
      testWidgets('unset stop shows the warning placeholder [$locale]',
          (tester) async {
        var pickupTaps = 0, dropTaps = 0;
        await tester.pumpWidget(qdApp(
          QdRouteStops(
            pickup: QdRouteStop(
              caption: 'Pickup',
              value: 'Your current location',
              note: 'Next to the kiosk',
              placeholder: 'Choose',
              onTap: () => pickupTaps++,
            ),
            dropoff: QdRouteStop(
              caption: 'Drop-off',
              placeholder: 'Choose the drop-off place',
              onTap: () => dropTaps++,
            ),
          ),
          locale: locale,
        ));
        expect(find.text('Next to the kiosk'), findsOneWidget);
        final placeholder =
            tester.widget<Text>(find.text('Choose the drop-off place'));
        expect(placeholder.style?.color, QdColors.light.warning);
        final value = tester.widget<Text>(find.text('Your current location'));
        expect(value.style?.color, QdColors.light.textPrimary);
        await tester.tap(find.text('Your current location'));
        await tester.tap(find.text('Choose the drop-off place'));
        expect((pickupTaps, dropTaps), (1, 1));
        expect(
            tester.getSize(find.ancestor(
                of: find.text('Drop-off'), matching: find.byType(InkWell))),
            isA<Size>()
                .having((s) => s.height, 'height', greaterThanOrEqualTo(64)));
      });
    }
  });

  group('QdPriceBreakdown', () {
    testWidgets('lines, total and note', (tester) async {
      await tester.pumpWidget(qdApp(const QdPriceBreakdown(
        lines: [
          QdPriceLine(label: 'Order opening', value: 'EGP 20'),
          QdPriceLine(label: '4 km × EGP 5', value: 'EGP 20'),
        ],
        totalLabel: 'Estimate',
        totalValue: 'About EGP 40',
        note: 'Straight-line estimate.',
      )));
      expect(find.text('Order opening'), findsOneWidget);
      expect(find.text('About EGP 40'), findsOneWidget);
      expect(find.text('Straight-line estimate.'), findsOneWidget);
      final total = tester.widget<Text>(find.text('About EGP 40'));
      expect(total.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('without total shows lines only', (tester) async {
      await tester.pumpWidget(qdApp(const QdPriceBreakdown(
        lines: [QdPriceLine(label: 'Per km', value: 'EGP 5')],
      )));
      expect(find.text('Per km'), findsOneWidget);
      expect(find.text('Estimate'), findsNothing);
    });
  });

  group('map overlay and bars', () {
    for (final locale in bothLocales) {
      testWidgets('render without overflow [$locale]', (tester) async {
        await tester.pumpWidget(qdApp(
          const Column(mainAxisSize: MainAxisSize.min, children: [
            QdMapPin(),
            QdMapLabel(label: 'Drop-off place'),
            QdDockedPanel(child: Text('panel')),
            QdFooterBar(child: Text('footer')),
          ]),
          locale: locale,
        ));
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(QdMapPin)).height, QdMapPin.height);
        expect(find.text('Drop-off place'), findsOneWidget);
        expect(find.text('panel'), findsOneWidget);
        expect(find.text('footer'), findsOneWidget);
      });
    }
  });

  testWidgets('QdFooterBar keeps its button height as bottomNavigationBar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: qdLightTheme,
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: QdFooterBar(
          child:
              QdButton(label: 'Order now', onPressed: () {}, fullWidth: true),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(QdButton)).height, QdSize.buttonHeight);
  });
}
