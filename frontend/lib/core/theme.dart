import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// STITCH DESIGN SYSTEM TOKENS - SINGLE SOURCE OF TRUTH
// ============================================================================

// 1. Color Palette (Stitch Kinetic Logistics & Nocturne Amber)
class AppColors {
  // Brand colors
  static const Color primary = Color(0xFF0D1321); // Deep Navy
  static const Color secondary = Color(0xFFFFC107); // Amber Gold
  static const Color background =
      Color(0xFFF9F9F9); // Light Gray surface background
  static const Color scaffoldBackground = Color(0xFFE5E7EB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFBA1A1A);

  // Text on colors
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFF0D1321);
  static const Color onBackground = Color(0xFF1A1C1C);
  static const Color onSurface = Color(0xFF1A1C1C);
  static const Color onError = Color(0xFFFFFFFF);

  // Variant surfaces & outlines
  static const Color surfaceDim = Color(0xFFDADADA);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF3F3F4);
  static const Color surfaceContainer = Color(0xFFEEEEEE);
  static const Color surfaceContainerHigh = Color(0xFFE8E8E8);
  static const Color surfaceContainerHighest = Color(0xFFE2E2E2);

  static const Color onSurfaceVariant = Color(0xFF45464C);

  // Status colors (WCAG AA compliant contrast ratios >= 4.5:1 on light surfaces)
  static const Color success =
      Color(0xFF15803D); // Dark Green (contrast 5.02:1 on white)
  static const Color danger =
      Color(0xFFBA1A1A); // Dark Red (contrast 10.1:1 on white)
  static const Color warning =
      Color(0xFFB45309); // Amber-700 (contrast 5.02:1 on white)

  // Outline & Dim colors
  static const Color outline = Color(
      0xFF57585E); // Dark Gray (contrast 5.61:1 on scaffold, 7.09:1 on white)
  static const Color outlineVariant =
      Color(0xFF8E8F95); // Mid Gray (contrast 3.34:1 for UI borders)
}

// Backwards-compatible global constants
const Color kBrandNavy = AppColors.primary;
const Color kBrandGold = AppColors.secondary;
const Color kBrandLightGray = AppColors.scaffoldBackground;
const Color kBrandWhite = AppColors.surface;
const Color kStatusSuccess = AppColors.success;
const Color kStatusDanger = AppColors.danger;
const Color kStatusWarning = AppColors.warning;

// 2. Spacing Scale (8pt grid system)
class AppSpacing {
  static const double xs = 4.0;
  static const double base = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double gutter = 16.0;
  static const double marginMobile = 16.0;
  static const double marginDesktop = 48.0;
}

// 3. Border Radius Scale
class AppRadius {
  static const double sm = 4.0;
  static const double defaultValue = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 9999.0;

  static BorderRadius get smBorder => BorderRadius.circular(sm);
  static BorderRadius get defaultBorder => BorderRadius.circular(defaultValue);
  static BorderRadius get mdBorder => BorderRadius.circular(md);
  static BorderRadius get lgBorder => BorderRadius.circular(lg);
  static BorderRadius get xlBorder => BorderRadius.circular(xl);
  static BorderRadius get fullBorder => BorderRadius.circular(full);
}

// 4. Elevation & Shadows (Tonal layers + Ambient shadows)
class AppShadows {
  static const BoxShadow level1 = BoxShadow(
    color: Color(0x140D1321), // rgba(13, 19, 33, 0.08)
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: 0,
  );

  static const BoxShadow level2 = BoxShadow(
    color: Color(0x1F0D1321), // rgba(13, 19, 33, 0.12)
    offset: Offset(0, 4),
    blurRadius: 16,
    spreadRadius: 0,
  );
}

// 5. Typography Scale
class AppTypography {
  static TextStyle get displayLg => GoogleFonts.poppins(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        height: 56 / 48,
        letterSpacing: -48 * 0.02,
      );

  static TextStyle get headlineLg => GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 40 / 32,
      );

  static TextStyle get headlineLgMobile => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 32 / 24,
      );

  static TextStyle get titleMd => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
      );

  static TextStyle get bodyLg => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        height: 24 / 16,
      );

  static TextStyle get bodyMd => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        height: 20 / 14,
      );

  static TextStyle get labelLg => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 12 * 0.05,
      );

  static TextStyle get labelMd => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 14 / 11,
      );
}

// ThemeData light setup
final ThemeData quickDeliveryTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    error: AppColors.error,
    onError: AppColors.onError,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
  ),
  scaffoldBackgroundColor: AppColors.scaffoldBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    elevation: 0,
  ),
  textTheme: GoogleFonts.poppinsTextTheme(),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.defaultValue),
      ),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.secondary,
    foregroundColor: AppColors.onSecondary,
  ),
);

// ThemeData dark setup
final ColorScheme _darkBaseScheme = ColorScheme.fromSeed(
  seedColor: AppColors.primary,
  brightness: Brightness.dark,
);

final ThemeData quickDeliveryDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _darkBaseScheme.copyWith(
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: const Color(0xFF594300),
    onSecondaryContainer: const Color(0xFFFFDF9E),
  ),
  scaffoldBackgroundColor: _darkBaseScheme.surface,
  appBarTheme: AppBarTheme(
    backgroundColor: _darkBaseScheme.surface,
    foregroundColor: _darkBaseScheme.onSurface,
    elevation: 0,
  ),
  textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.defaultValue),
      ),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.secondary,
    foregroundColor: AppColors.onSecondary,
  ),
);
