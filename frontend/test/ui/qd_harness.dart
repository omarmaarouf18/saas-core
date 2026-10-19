import 'package:flutter/material.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/qd_theme.dart';

const ar = Locale('ar');
const en = Locale('en');

/// Pumps [child] under the redesign theme in [locale] (Arabic → RTL).
Widget qdApp(Widget child, {Locale locale = ar, bool scroll = false}) {
  final body = Padding(padding: const EdgeInsets.all(16), child: child);
  return MaterialApp(
    theme: qdLightTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: scroll ? SingleChildScrollView(child: body) : Center(child: body),
    ),
  );
}

/// Arabic then English: every component must render both directions.
const bothLocales = [ar, en];
