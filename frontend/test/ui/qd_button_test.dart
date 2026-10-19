import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_button.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  for (final locale in bothLocales) {
    testWidgets('primary taps and is gold [$locale]', (tester) async {
      var taps = 0;
      await tester.pumpWidget(qdApp(
          QdButton(label: 'Order now', onPressed: () => taps++),
          locale: locale));
      await tester.tap(find.text('Order now'));
      expect(taps, 1);
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(QdButton), matching: find.byType(Material))
          .first);
      expect(material.color, QdColors.light.gold);
      expect(_labelColor(tester, 'Order now'), QdColors.light.onGold);
      expect(tester.getSize(find.byType(QdButton)).height,
          greaterThanOrEqualTo(48));
    });
  }

  testWidgets('disabled: grey fill, no tap, semantics disabled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        qdApp(const QdButton(label: 'Pick drop-off', onPressed: null)));
    final material = tester.widget<Material>(find
        .descendant(of: find.byType(QdButton), matching: find.byType(Material))
        .first);
    expect(material.color, QdColors.light.disabledFill);
    expect(
      tester.getSemantics(find.byType(QdButton)),
      matchesSemantics(
          label: 'Pick drop-off', isButton: true, hasEnabledState: true),
    );
    handle.dispose();
  });

  testWidgets('loading shows a spinner, ignores taps, announces loading',
      (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(qdApp(
        QdButton(label: 'Log in', onPressed: () => taps++, loading: true),
        locale: en));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
    await tester.tap(find.byType(QdButton));
    expect(taps, 0);
    expect(tester.getSemantics(find.byType(QdButton)).label, 'Log in, Loading');
    handle.dispose();
  });

  testWidgets('full width fills the parent', (tester) async {
    await tester.pumpWidget(
        qdApp(QdButton(label: 'Go', onPressed: () {}, fullWidth: true)));
    final screen = tester.getSize(find.byType(Scaffold)).width;
    expect(tester.getSize(find.byType(QdButton)).width, screen - 32);
  });

  testWidgets('secondary, text and destructive colors and 48 dp targets',
      (tester) async {
    await tester
        .pumpWidget(qdApp(Column(mainAxisSize: MainAxisSize.min, children: [
      QdButton.secondary(label: 'Decline', onPressed: () {}),
      QdButton.text(label: 'Forgot password?', onPressed: () {}),
      QdButton.destructive(label: 'Cancel order', onPressed: () {}),
      QdButton(label: 'Reply', onPressed: () {}, small: true),
    ])));
    expect(_labelColor(tester, 'Decline'), QdColors.light.textPrimary);
    expect(_labelColor(tester, 'Forgot password?'), QdColors.light.textPrimary);
    expect(_labelColor(tester, 'Cancel order'), QdColors.light.danger);
    for (final b in tester.widgetList<QdButton>(find.byType(QdButton))) {
      expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(48),
          reason: b.label);
    }
  });
}
