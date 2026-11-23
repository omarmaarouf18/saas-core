import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_brand_mark.dart';

void main() {
  testWidgets('QdBrandMark renders standalone with Waddify semantics',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QdBrandMark(size: 48, variant: QdBrandMarkVariant.full),
          ),
        ),
      ),
    );

    expect(find.byType(QdBrandMark), findsOneWidget);
    expect(find.bySemanticsLabel('Waddify'), findsOneWidget);
  });

  testWidgets('QdBrandMark renders onDark variant', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QdBrandMark(size: 56, variant: QdBrandMarkVariant.onDark),
          ),
        ),
      ),
    );

    expect(find.byType(QdBrandMark), findsOneWidget);
  });

  testWidgets('QdBrandMark renders mono variant with custom color',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QdBrandMark(
              size: 32,
              variant: QdBrandMarkVariant.mono,
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(QdBrandMark), findsOneWidget);
  });

  testWidgets('QdBrandMark renders small sizes below 24px and below 48px',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              QdBrandMark(size: 20, variant: QdBrandMarkVariant.full),
              QdBrandMark(size: 36, variant: QdBrandMarkVariant.onDark),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(QdBrandMark), findsNWidgets(2));
  });
}
