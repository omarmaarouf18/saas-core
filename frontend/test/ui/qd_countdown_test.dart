import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_countdown.dart';

import 'qd_harness.dart';

void main() {
  test('format is mm:ss, rounds up, never negative', () {
    expect(QdCountdown.format(const Duration(seconds: 25)), '00:25');
    expect(
        QdCountdown.format(const Duration(minutes: 2, seconds: 41)), '02:41');
    expect(QdCountdown.format(const Duration(milliseconds: 24100)), '00:25');
    expect(QdCountdown.format(Duration.zero), '00:00');
    expect(QdCountdown.format(const Duration(seconds: -5)), '00:00');
  });

  for (final style in QdCountdownStyle.values) {
    for (final locale in bothLocales) {
      testWidgets('$style ticks down and fires onExpired once [$locale]',
          (tester) async {
        var now = DateTime(2026, 10, 19, 12);
        final expiry = now.add(const Duration(seconds: 3));
        var expired = 0;
        await tester.pumpWidget(qdApp(
          QdCountdown(
            expiresAt: expiry,
            total: const Duration(seconds: 30),
            style: style,
            label: style == QdCountdownStyle.bar ? 'Offer ends in' : null,
            now: () => now,
            onExpired: () => expired++,
          ),
          locale: locale,
        ));
        expect(find.text('00:03'), findsOneWidget);

        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('00:02'), findsOneWidget);
        expect(expired, 0);

        now = now.add(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('00:00'), findsOneWidget);
        expect(expired, 1);

        await tester.pump(const Duration(seconds: 2));
        expect(expired, 1);
      });
    }
  }

  testWidgets('already expired fires on first build', (tester) async {
    final now = DateTime(2026, 10, 19, 12);
    var expired = 0;
    await tester.pumpWidget(qdApp(QdCountdown(
      expiresAt: now.subtract(const Duration(seconds: 1)),
      total: const Duration(seconds: 30),
      now: () => now,
      onExpired: () => expired++,
    )));
    await tester.pump();
    expect(expired, 1);
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('bar width is remaining / total', (tester) async {
    final now = DateTime(2026, 10, 19, 12);
    await tester.pumpWidget(qdApp(QdCountdown(
      expiresAt: now.add(const Duration(seconds: 15)),
      total: const Duration(seconds: 60),
      style: QdCountdownStyle.bar,
      now: () => now,
    )));
    final bar =
        tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
    expect(bar.widthFactor, closeTo(0.25, 0.001));
  });

  testWidgets('new expiry re-arms onExpired', (tester) async {
    var now = DateTime(2026, 10, 19, 12);
    var expired = 0;
    Widget build(DateTime expiry) => qdApp(QdCountdown(
          expiresAt: expiry,
          total: const Duration(seconds: 30),
          now: () => now,
          onExpired: () => expired++,
        ));
    await tester.pumpWidget(build(now.add(const Duration(seconds: 1))));
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(expired, 1);
    await tester.pumpWidget(build(now.add(const Duration(seconds: 1))));
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(expired, 2);
  });

  testWidgets('announces time left', (tester) async {
    final handle = tester.ensureSemantics();
    final now = DateTime(2026, 10, 19, 12);
    await tester.pumpWidget(qdApp(
        QdCountdown(
          expiresAt: now.add(const Duration(seconds: 25)),
          total: const Duration(seconds: 30),
          now: () => now,
        ),
        locale: en));
    expect(find.bySemanticsLabel('00:25 left'), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
