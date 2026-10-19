import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/components/qd_money.dart';

void main() {
  final arL10n = lookupAppLocalizations(const Locale('ar'));
  final enL10n = lookupAppLocalizations(const Locale('en'));

  test('Arabic puts ج.م after the amount', () {
    expect(QdMoney.format(arL10n, 45), '45 ج.م');
    expect(QdMoney.format(arL10n, 1250), '1,250 ج.م');
  });

  test('English puts EGP before the amount', () {
    expect(QdMoney.format(enL10n, 45), 'EGP 45');
    expect(QdMoney.format(enL10n, 1250), 'EGP 1,250');
  });

  test('whole amounts have no decimals, fractions always two', () {
    expect(QdMoney.format(enL10n, 45.0), 'EGP 45');
    expect(QdMoney.format(enL10n, 45.5), 'EGP 45.50');
    expect(QdMoney.format(enL10n, 1234.56), 'EGP 1,234.56');
    expect(QdMoney.format(arL10n, 0.25), '0.25 ج.م');
    expect(QdMoney.format(enL10n, 99.999), 'EGP 100');
    expect(QdMoney.format(enL10n, 0), 'EGP 0');
  });

  test('Western digits in both languages, never a dollar sign', () {
    for (final l10n in [arL10n, enL10n]) {
      for (final v in [0, 7, 45.5, 12000]) {
        final s = QdMoney.format(l10n, v);
        expect(s, isNot(contains(r'$')));
        expect(RegExp('[٠-٩]').hasMatch(s), isFalse, reason: s);
      }
    }
  });
}
