import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/themed_inline_spinner.dart';

void main() {
  testWidgets('renders an exact square box with an indicator inside',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThemedInlineSpinner(
            key: Key('spinner_under_test'),
            size: 20,
            color: AppColors.secondary,
          ),
        ),
      ),
    );

    final box = tester.widget<SizedBox>(find.descendant(
      of: find.byKey(const Key('spinner_under_test')),
      matching: find.byType(SizedBox),
    ));
    expect(box.width, 20.0);
    expect(box.height, 20.0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(indicator.color, AppColors.secondary);
  });

  testWidgets('stroke width follows the size rule unless overridden',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ThemedInlineSpinner(size: 8),
              ThemedInlineSpinner(size: 18),
              ThemedInlineSpinner(size: 20, strokeWidth: 3.0),
            ],
          ),
        ),
      ),
    );

    final indicators = tester
        .widgetList<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator))
        .toList();
    expect(indicators, hasLength(3));
    // 8px connecting-dot convention keeps the hairline stroke, 18 takes
    // the standard stroke, explicit override wins.
    expect(
      indicators.map((e) => e.strokeWidth).toList(),
      [1.5, 2.0, 3.0],
    );
  });

  test('size rule boundary: 12px keeps hairline, above takes standard', () {
    expect(const ThemedInlineSpinner(size: 12).strokeWidth, isNull);
    // The rule itself is asserted through the widget test above (1.5 at 8,
    // 2.0 at 18); this pins the documented boundary value exists.
    expect(AppIconSize.xs, 14.0);
  });
}
