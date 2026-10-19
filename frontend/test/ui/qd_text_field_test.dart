import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_text_field.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

EditableText _editable(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText));

void main() {
  for (final locale in bothLocales) {
    testWidgets('label sits above the field, hint inside [$locale]',
        (tester) async {
      await tester.pumpWidget(qdApp(
          const QdTextField(label: 'Email', hint: 'name@example.com'),
          locale: locale));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('name@example.com'), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Email')).dy,
          lessThan(tester.getTopLeft(find.byType(TextField)).dy));
      expect(tester.getSize(find.byType(TextField)).height,
          greaterThanOrEqualTo(48));
    });
  }

  testWidgets('error text shows below in danger', (tester) async {
    await tester.pumpWidget(qdApp(
        const QdTextField(label: 'Password', errorText: 'Wrong password')));
    final error = tester.widget<Text>(find.text('Wrong password'));
    expect(error.style?.color, QdColors.light.danger);
    expect(tester.getTopLeft(find.text('Wrong password')).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField)).dy));
  });

  testWidgets('password toggle shows and hides the text', (tester) async {
    await tester.pumpWidget(
        qdApp(const QdTextField(label: 'Password', obscure: true), locale: en));
    expect(_editable(tester).obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(_editable(tester).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('LTR field inside RTL stays LTR, right-aligned', (tester) async {
    await tester.pumpWidget(qdApp(const QdTextField(
        label: 'الموبايل', ltr: true, keyboardType: TextInputType.phone)));
    expect(_editable(tester).textDirection, TextDirection.ltr);
    expect(_editable(tester).textAlign, TextAlign.right);
  });

  testWidgets('RTL field follows the screen direction', (tester) async {
    await tester.pumpWidget(qdApp(const QdTextField(label: 'الاسم')));
    expect(_editable(tester).textDirection, TextDirection.rtl);
    expect(_editable(tester).textAlign, TextAlign.start);
  });

  testWidgets('field is announced with its visible label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester
        .pumpWidget(qdApp(const QdTextField(label: 'Email'), locale: en));
    expect(find.bySemanticsLabel('Email'), findsOneWidget);
    handle.dispose();
  });
}
