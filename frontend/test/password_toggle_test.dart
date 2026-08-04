import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme.dart';
import 'package:frontend/widgets/themed_text_field.dart';

void main() {
  group('ThemedTextField Password Visibility Toggle Tests', () {
    testWidgets(
        'renders password visibility toggle icon when isPasswordField is true and toggles obscure state',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: 'secret123');

      await tester.pumpWidget(
        MaterialApp(
          theme: quickDeliveryTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ThemedTextField(
                controller: controller,
                labelText: 'Password',
                isPasswordField: true,
              ),
            ),
          ),
        ),
      );

      final editableTextFinder = find.byType(EditableText);
      expect(editableTextFinder, findsOneWidget);
      EditableText editableText = tester.widget(editableTextFinder);
      expect(editableText.obscureText, isTrue);

      final toggleButtonFinder = find.byKey(const Key('password_toggle_button'));
      expect(toggleButtonFinder, findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      await tester.tap(toggleButtonFinder);
      await tester.pump();

      editableText = tester.widget(editableTextFinder);
      expect(editableText.obscureText, isFalse);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      await tester.tap(toggleButtonFinder);
      await tester.pump();

      editableText = tester.widget(editableTextFinder);
      expect(editableText.obscureText, isTrue);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets(
        'automatically enables password toggle when obscureText is true',
        (WidgetTester tester) async {
      final controller = TextEditingController(text: 'pass123');

      await tester.pumpWidget(
        MaterialApp(
          theme: quickDeliveryTheme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ThemedTextField(
                controller: controller,
                labelText: 'User Password',
                obscureText: true,
              ),
            ),
          ),
        ),
      );

      final toggleButtonFinder = find.byKey(const Key('password_toggle_button'));
      expect(toggleButtonFinder, findsOneWidget);

      EditableText editableText = tester.widget(find.byType(EditableText));
      expect(editableText.obscureText, isTrue);

      await tester.tap(toggleButtonFinder);
      await tester.pump();

      editableText = tester.widget(find.byType(EditableText));
      expect(editableText.obscureText, isFalse);
    });
  });
}
