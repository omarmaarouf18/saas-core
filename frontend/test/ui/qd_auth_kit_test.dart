import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/qd_ui.dart';

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: qdLightTheme,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child)),
    );

void main() {
  group('QdOtpInput', () {
    test('digitsOf keeps digits only, up to the length', () {
      expect(QdOtpInput.digitsOf('12 34-56', 6), '123456');
      expect(QdOtpInput.digitsOf('1234567', 6), '123456');
      expect(QdOtpInput.digitsOf('ab', 6), '');
    });

    testWidgets('typing fills the boxes and completes at 6 digits',
        (tester) async {
      final changes = <String>[];
      String? completed;
      await tester.pumpWidget(_app(QdOtpInput(
        semanticLabel: 'Code',
        onChanged: changes.add,
        onCompleted: (v) => completed = v,
      )));
      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(completed, isNull);

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(completed, '123456');
      expect(changes.last, '123456');
    });

    testWidgets('a pasted code with spaces and dashes fills every box',
        (tester) async {
      final controller = TextEditingController();
      String? completed;
      await tester.pumpWidget(_app(QdOtpInput(
        semanticLabel: 'Code',
        controller: controller,
        onCompleted: (v) => completed = v,
      )));
      await tester.enterText(find.byType(TextField), '98 76-54 extra 3');
      await tester.pump();
      expect(controller.text, '987654');
      expect(completed, '987654');
      for (final d in ['9', '8', '7', '6', '5', '4']) {
        expect(find.text(d), findsOneWidget);
      }
    });

    testWidgets('a value set from outside is cleaned', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
          _app(QdOtpInput(semanticLabel: 'Code', controller: controller)));
      controller.text = '12-34';
      await tester.pump();
      expect(controller.text, '1234');
    });

    testWidgets('digits stay left to right in Arabic', (tester) async {
      await tester.pumpWidget(_app(const QdOtpInput(semanticLabel: 'Code'),
          locale: const Locale('ar')));
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(tester.getCenter(find.text('1')).dx,
          lessThan(tester.getCenter(find.text('2')).dx));
    });

    testWidgets('has an accessible name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
          _app(const QdOtpInput(semanticLabel: 'Verification code')));
      expect(find.bySemanticsLabel('Verification code'), findsOneWidget);
      handle.dispose();
    });
  });

  group('QdOptionCard', () {
    testWidgets('selected state, tap and semantics', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(_app(QdOptionCard(
        title: 'Customer',
        subtitle: 'I want to send orders',
        selected: true,
        onTap: () => taps++,
      )));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.tap(find.byType(QdOptionCard));
      expect(taps, 1);
      final node = tester.getSemantics(find.byType(QdOptionCard));
      expect(node.label, 'Customer, I want to send orders');
      expect(node.flagsCollection.isChecked, CheckedState.isTrue);
      expect(tester.getSize(find.byType(QdOptionCard)).height,
          greaterThanOrEqualTo(48));
      handle.dispose();
    });
  });
}
