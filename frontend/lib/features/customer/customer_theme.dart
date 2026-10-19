import 'package:flutter/material.dart';

import '../../ui/qd_theme.dart';

/// Wraps a redesigned customer subtree in the redesign A theme: light, or
/// dark when the app around it is dark. The app-wide theme is unchanged, so
/// old screens pushed from here keep their look.
class CustomerTheme extends StatelessWidget {
  const CustomerTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(data: dark ? qdDarkTheme : qdLightTheme, child: child);
  }
}

/// A page route whose page renders under [CustomerTheme]. Routes live in the
/// navigator's overlay, outside the shell's theme, so every new customer
/// page is pushed with this.
Route<T> customerRoute<T>(WidgetBuilder builder) => MaterialPageRoute<T>(
      builder: (context) => CustomerTheme(child: Builder(builder: builder)),
    );
