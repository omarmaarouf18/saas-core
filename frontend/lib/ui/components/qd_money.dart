import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';

/// Egyptian-pound formatter (FE-DS). Arabic: `45 ج.م`, English: `EGP 45`.
///
/// The currency placement comes from the `qdMoneyAmount` ARB template; the
/// number is formatted by intl with Western digits and a thousands
/// separator in both languages, matching the mockups. Whole amounts have no
/// decimals, fractional amounts always two. Never `$`, never a bare number.
abstract final class QdMoney {
  static final NumberFormat _whole = NumberFormat('#,##0', 'en');
  static final NumberFormat _fraction = NumberFormat('#,##0.00', 'en');

  /// Formats [amount] with the given localizations.
  static String format(AppLocalizations l10n, num amount) {
    final rounded = (amount * 100).round() / 100;
    final isWhole = rounded == rounded.truncateToDouble();
    final number = (isWhole ? _whole : _fraction).format(rounded);
    return l10n.qdMoneyAmount(number);
  }

  /// Formats [amount] with the localizations of [context].
  static String of(BuildContext context, num amount) =>
      format(context.l10n, amount);
}
