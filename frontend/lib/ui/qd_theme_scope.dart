import 'package:flutter/material.dart';

import 'qd_theme.dart';

/// Renders [child] under the redesign A theme: light, or dark when the app
/// around it is dark. The app-wide theme is not touched, so old screens
/// pushed from a redesigned page keep their look (same idea as the
/// customer feature's CustomerTheme, for pages outside the customer shell).
class QdThemeScope extends StatelessWidget {
  const QdThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(data: dark ? qdDarkTheme : qdLightTheme, child: child);
  }
}

/// A page route whose page renders under [QdThemeScope]. Routes live in the
/// navigator overlay, outside any ancestor Theme, so redesigned pages are
/// pushed with this.
Route<T> qdPageRoute<T>(WidgetBuilder builder, {RouteSettings? settings}) =>
    MaterialPageRoute<T>(
      settings: settings,
      builder: (context) => QdThemeScope(child: Builder(builder: builder)),
    );
