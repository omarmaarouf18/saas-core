import 'package:flutter/material.dart';
import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsEn();
}

AppLocalizations appL10n(BuildContext context) {
  return AppLocalizations.of(context) ?? AppLocalizationsEn();
}
