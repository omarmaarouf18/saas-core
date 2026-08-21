import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/themed_panel.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders rectangular panel with color and radius',
      (tester) async {
    await tester.pumpWidget(_host(const ThemedPanel(
      key: Key('panel'),
      color: AppColors.primary,
      borderRadius: BorderRadius.all(Radius.circular(8)),
      padding: EdgeInsets.all(8),
      child: Text('content'),
    )));

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, AppColors.primary);
    expect(decoration.borderRadius, isNotNull);
  });

  testWidgets('renders circular shape without borderRadius assertion',
      (tester) async {
    await tester.pumpWidget(_host(const ThemedPanel(
      shape: BoxShape.circle,
      color: AppColors.secondary,
      child: Icon(Icons.star),
    )));

    final decoration = tester
        .widget<Container>(find.byType(Container))
        .decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
  });

  testWidgets('applies gradient when provided', (tester) async {
    const gradient = LinearGradient(
      colors: [AppColors.primaryContainer, AppColors.primary],
    );
    await tester.pumpWidget(_host(const ThemedPanel(
      gradient: gradient,
      child: SizedBox(height: 20),
    )));

    final decoration = tester
        .widget<Container>(find.byType(Container))
        .decoration! as BoxDecoration;
    expect(decoration.gradient, gradient);
  });

  testWidgets('onTap wraps in InkWell', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(ThemedPanel(
      onTap: () => tapped = true,
      color: AppColors.surface,
      child: const Text('tap me'),
    )));

    await tester.tap(find.text('tap me'));
    expect(tapped, true);
  });

  testWidgets('AnimatedThemedPanel animates between colors', (tester) async {
    late StateSetter setState;
    var selected = false;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, st) {
        setState = st;
        return AnimatedThemedPanel(
          duration: const Duration(milliseconds: 100),
          color: selected ? AppColors.success : AppColors.error,
          child: const Text('animated'),
        );
      },
    )));

    BoxDecoration decorationAt(String text) {
      return tester
          .widget<Container>(find
              .ancestor(of: find.text(text), matching: find.byType(Container))
              .first)
          .decoration! as BoxDecoration;
    }

    expect(decorationAt('animated').color, AppColors.error);
    setState(() => selected = true);
    await tester.pump(); // start animation
    await tester.pump(const Duration(milliseconds: 150)); // finish
    expect(decorationAt('animated').color, AppColors.success);
  });
}
