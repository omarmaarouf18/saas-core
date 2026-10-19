import 'package:flutter/material.dart';

import 'tokens.dart';

/// Redesign A [ThemeData] built from [QdColors] / [QdText] (FE-DS).
///
/// NOT wired into the app yet: `main.dart` still uses the legacy
/// `quickDeliveryTheme`. The screen rebuild tasks (FE-CUST-1 onward) switch
/// over; until then this theme is used by the debug gallery and tests only.
ThemeData buildQdTheme({Brightness brightness = Brightness.light}) {
  final c = brightness == Brightness.dark ? QdColors.dark : QdColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.gold,
    onPrimary: c.onGold,
    primaryContainer: c.goldTint,
    onPrimaryContainer: c.textPrimary,
    secondary: c.navy,
    onSecondary: c.onNavy,
    error: c.danger,
    onError: c.surface,
    errorContainer: c.dangerBg,
    onErrorContainer: c.danger,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.fillSubtle,
    surfaceContainer: c.fillSubtle,
    surfaceContainerHigh: c.fillMuted,
    surfaceContainerHighest: c.fillMuted,
    outline: c.borderInput,
    outlineVariant: c.border,
    scrim: c.scrim,
    shadow: c.scrim,
  );

  TextStyle t(TextStyle s, [Color? color]) =>
      s.copyWith(color: color ?? c.textPrimary);

  final textTheme = TextTheme(
    displaySmall: t(QdText.screenTitleLg),
    headlineMedium: t(QdText.screenTitle),
    headlineSmall: t(QdText.sheetTitle),
    titleLarge: t(QdText.header),
    titleMedium: t(QdText.rowTitle),
    titleSmall: t(QdText.rowTitleSm),
    bodyLarge: t(QdText.body),
    bodyMedium: t(QdText.body),
    bodySmall: t(QdText.secondary, c.textSecondary),
    labelLarge: t(QdText.buttonSm),
    labelMedium: t(QdText.caption, c.textSecondary),
    labelSmall: t(QdText.chip),
  );

  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(QdRadius.sm),
    borderSide: BorderSide(color: c.borderInput),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kQdFontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    dividerColor: c.border,
    extensions: <ThemeExtension<dynamic>>[c],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t(QdText.header),
    ),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding:
          const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 15),
      hintStyle: t(QdText.body, c.textSecondary),
      errorStyle: t(QdText.caption, c.danger),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.textPrimary, width: 2)),
      errorBorder:
          fieldBorder.copyWith(borderSide: BorderSide(color: c.danger)),
      focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.gold,
        foregroundColor: c.onGold,
        disabledBackgroundColor: c.disabledFill,
        disabledForegroundColor: c.neutral,
        minimumSize: const Size(QdSize.minTouch, QdSize.buttonHeight),
        textStyle: QdText.button,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QdRadius.button)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.borderInput),
        minimumSize: const Size(QdSize.minTouch, QdSize.buttonHeight),
        textStyle: QdText.rowTitleSm,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QdRadius.button)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textPrimary,
        minimumSize: const Size(QdSize.minTouch, QdSize.minTouch),
        textStyle: QdText.bodyStrong,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? c.surface : c.textSecondary),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.navy : c.fillMuted),
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.navy : c.borderInput),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.navy,
      linearTrackColor: c.border,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.navy,
      contentTextStyle: t(QdText.body, c.surface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QdRadius.sm)),
    ),
  );
}

/// Light theme (the approved look).
final ThemeData qdLightTheme = buildQdTheme();

/// Dark theme (navy surfaces, same gold rules). Kept simple; not wired.
final ThemeData qdDarkTheme = buildQdTheme(brightness: Brightness.dark);
