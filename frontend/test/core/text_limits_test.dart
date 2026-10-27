import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/text_limits.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/components/qd_text_field.dart';
import 'package:frontend/ui/qd_theme.dart';

/// "بِسْمِ" : 3 letters + 3 diacritics = 6 runes, 3 grapheme clusters.
const _withDiacritics = 'بِسْمِ';

void main() {
  test('limits match the services (runes)', () {
    expect(kAddressTextMaxRunes, 250);
    expect(kAddressNoteMaxRunes, 500);
    expect(kNotesMaxRunes, 200);
    expect(kNameMaxRunes, 100);
  });

  test('runeLength counts code points, not bytes or graphemes', () {
    expect(runeLength('abc'), 3);
    expect(runeLength('شارع'), 4); // 8 UTF-8 bytes
    expect(runeLength(_withDiacritics), 6);
    expect(_withDiacritics.characters.length, 3);
    expect(runeLength('🙂'), 1); // 2 UTF-16 units, 4 bytes
  });

  group('RuneLimitingTextInputFormatter', () {
    TextEditingValue fmt(int max, String oldText, String newText) =>
        RuneLimitingTextInputFormatter(max).formatEditUpdate(
          TextEditingValue(text: oldText),
          TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newText.length)),
        );

    test('within the limit: unchanged', () {
      expect(fmt(4, 'شار', 'شارع').text, 'شارع');
    });

    test('over: cut at a code point, never inside an emoji', () {
      expect(fmt(3, '', 'ab🙂🙂').text, 'ab🙂');
      expect(fmt(4, '', _withDiacritics).text, 'بِسْ');
      final v = fmt(2, 'a', 'abc');
      expect((v.text, v.selection.baseOffset), ('ab', 2));
    });
  });

  testWidgets('QdTextField counter shows characters the server counts',
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      theme: qdLightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: QdTextField(label: 'Notes', controller: c, maxRunes: 5)),
    ));
    expect(find.text('0 / 5'), findsOneWidget);
    await tester.enterText(find.byType(TextField), _withDiacritics);
    await tester.pump();
    // 6 runes typed, cut to 5; Flutter's own counter would say 3.
    expect(c.text.runes.length, 5);
    expect(find.text('5 / 5'), findsOneWidget);
    // An error keeps the counter.
    await tester.pumpWidget(MaterialApp(
      theme: qdLightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: QdTextField(
              label: 'Notes', controller: c, maxRunes: 5, errorText: 'Bad')),
    ));
    expect(find.text('Bad'), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);
  });

  test('no input limit counts grapheme clusters for a server field', () {
    // Guard: the booking fields use maxRunes, not the grapheme-based
    // LengthLimitingTextInputFormatter.
    final f = LengthLimitingTextInputFormatter(3);
    final v = f.formatEditUpdate(
        TextEditingValue.empty, const TextEditingValue(text: _withDiacritics));
    expect(v.text, _withDiacritics, reason: 'Flutter lets 6 runes through');
  });

  test('no text length is counted in UTF-8 bytes, except the password', () {
    // The password stays in bytes on purpose: bcrypt (auth-service) reads
    // at most 72 bytes.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/l10n/')) continue;
      final src = f.readAsStringSync();
      if (src.contains('utf8.encode(') &&
          !f.path.endsWith('core/password_policy.dart')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
