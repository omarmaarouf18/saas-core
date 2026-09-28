import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F3 label rules: no parentheses in user-facing ARB copy. Units and
/// currency live in the input's suffixText/prefixText, "optional" is a
/// trailing "· optional", read-only state is a lock icon + helper text,
/// acronyms expand to plain words, examples use a comma — never "(...)".
/// This test fails if any `app_en.arb` / `app_ar.arb` value reintroduces
/// "(" or ")" outside [kAllowedParens].
///
/// Allowlist (key -> reason). Placeholders like {x} use braces and are
/// always fine — only round parens are checked.
/// Currently EMPTY: every legitimate case was rewritten during F3, so a new
/// paren must be justified here with a reason before it can land.
const Map<String, String> kAllowedParens = <String, String>{};

Map<String, dynamic> _loadArb(String name) {
  final file = File('lib/l10n/$name');
  expect(file.existsSync(), isTrue,
      reason: 'must run from frontend/ directory');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  test('EN and AR ARB files keep exact key parity', () {
    final en = _loadArb('app_en.arb');
    final ar = _loadArb('app_ar.arb');
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();
    final arKeys = ar.keys.where((k) => !k.startsWith('@')).toSet();
    expect(arKeys.difference(enKeys), isEmpty,
        reason: 'keys in AR missing from EN');
    expect(enKeys.difference(arKeys), isEmpty,
        reason: 'keys in EN missing from AR');
  });

  test('no parentheses in ARB values outside the explicit allowlist', () {
    final offenders = <String>[];
    for (final name in ['app_en.arb', 'app_ar.arb']) {
      final arb = _loadArb(name);
      for (final entry in arb.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key.startsWith('@')) continue; // metadata, not user copy
        if (value is! String) continue;
        if (!value.contains('(') && !value.contains(')')) continue;
        if (kAllowedParens.containsKey(key)) continue;
        offenders.add('$name:$key = ${value.toString()}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'parenthesized copy must be rewritten per F3 label rules '
            '(suffixText/prefixText, "· optional", comma examples) or '
            'justified in kAllowedParens:\n${offenders.join('\n')}');
  });

  test('every allowlisted key still exists and documents a reason', () {
    final en = _loadArb('app_en.arb');
    final ar = _loadArb('app_ar.arb');
    for (final entry in kAllowedParens.entries) {
      expect(entry.value.trim(), isNotEmpty,
          reason: 'allowlist entry ${entry.key} needs a reason');
      expect(en.containsKey(entry.key) || ar.containsKey(entry.key), isTrue,
          reason: 'allowlist entry ${entry.key} no longer exists — remove it');
    }
  });

  test('unit/currency labels carry no inline unit text', () {
    final en = _loadArb('app_en.arb')..addAll(_loadArb('app_ar.arb'));
    const unitLabels = [
      'ownerConfigRadiusLabel',
      'ownerConfigBasePriceLabel',
      'ownerConfigPricePerKmLabel',
      'customerMarketplaceFilterRadius',
      'walletAmountCredits',
    ];
    for (final key in unitLabels) {
      final value = en[key] as String;
      expect(value.contains('('), isFalse, reason: '$key has parens');
      expect(value.contains(')'), isFalse, reason: '$key has parens');
      expect(RegExp(r'\$|km|KM|credits', caseSensitive: false).hasMatch(value),
          isFalse,
          reason: '$key carries inline unit/currency "$value" — '
              'use suffixText/prefixText instead');
    }
  });
}
