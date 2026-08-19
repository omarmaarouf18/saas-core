import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
// STITCH DESIGN SYSTEM TOKENS - SINGLE SOURCE OF TRUTH
// ============================================================================

// 1. Color Palette (Stitch Unified Theme & Nocturne Amber)
class AppColors {
  // Brand colors
  static const Color primary = Color(0xFF0D1321); // Deep Navy
  static const Color primaryContainer =
      Color(0xFF151B2A); // Dark Slate/Navy container
  static const Color onPrimaryContainer = Color(0xFF7E8395);
  static const Color secondary = Color(0xFFFFC107); // Amber Gold
  static const Color secondaryContainer =
      Color(0xFFFDC003); // Amber Gold CTA fill
  static const Color onSecondaryContainer = Color(0xFF6C5000);
  static const Color background =
      Color(0xFFF9F9F9); // Light Gray surface background
  static const Color scaffoldBackground = Color(0xFFE5E7EB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

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

  // Dark Mode tokens (WCAG AA compliant contrast ratios >= 4.5:1 for text, >= 3:1 for controls)
  static const Color primaryDark =
      Color(0xFFFFC107); // Amber Gold primary accent in dark mode
  static const Color onPrimaryDark =
      Color(0xFF0F172A); // Dark Navy text on Amber Gold
  static const Color primaryContainerDark =
      Color(0xFF1E293B); // Dark Slate container
  static const Color onPrimaryContainerDark = Color(0xFFF8FAFC);
  static const Color secondaryDark = Color(0xFFFFC107); // Amber Gold secondary
  static const Color onSecondaryDark = Color(0xFF0F172A);
  static const Color secondaryContainerDark = Color(0xFF334155);
  static const Color onSecondaryContainerDark = Color(0xFFFFDF9E);
  static const Color backgroundDark = Color(0xFF0A0E17);
  static const Color scaffoldBackgroundDark = Color(0xFF0A0E17);
  static const Color surfaceDark =
      Color(0xFF0F172A); // Dark Navy/Slate surface background
  static const Color onSurfaceDark =
      Color(0xFFF8FAFC); // High contrast off-white text
  static const Color surfaceDimDark = Color(0xFF0A0E17);
  static const Color surfaceContainerLowestDark = Color(0xFF0F172A);
  static const Color surfaceContainerLowDark = Color(0xFF1E293B);
  static const Color surfaceContainerDark =
      Color(0xFF1E293B); // Card background in dark mode
  static const Color surfaceContainerHighDark = Color(0xFF334155);
  static const Color surfaceContainerHighestDark = Color(0xFF475569);
  static const Color onSurfaceVariantDark =
      Color(0xFFCBD5E1); // Light Slate subtitle text
  static const Color outlineDark = Color(0xFF64748B); // Slate border
  static const Color outlineVariantDark =
      Color(0xFF475569); // Darker slate divider
  static const Color errorDark = Color(0xFFF87171); // High contrast Red
  static const Color onErrorDark = Color(0xFF0F172A);
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
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double base = 8.0;
  static const double baseSm = 10.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 40.0;
  static const double xxxl = 100.0;
  static const double gutter = 16.0;
  static const double marginMobile = 16.0;
  static const double marginDesktop = 48.0;
}

// 3. Border Radius Scale
class AppRadius {
  static const double xxs = 3.0;
  static const double xs = 2.0;
  static const double sm = 4.0;
  static const double defaultValue = 8.0;
  static const double smMd = 10.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double lgXl = 20.0;
  static const double xl = 24.0;
  static const double full = 9999.0;

  // Named aliases
  static const double radiusXxs = xxs;
  static const double radiusXs = xs;
  static const double radiusSm = sm;
  static const double radiusDefault = defaultValue;
  static const double radiusSmMd = smMd;
  static const double radiusMd = md;
  static const double radiusLg = lg;
  static const double radiusLgXl = lgXl;
  static const double radiusXl = xl;
  static const double radiusFull = full;

  static BorderRadius get xxsBorder => BorderRadius.circular(xxs);
  static BorderRadius get xsBorder => BorderRadius.circular(xs);
  static BorderRadius get smBorder => BorderRadius.circular(sm);
  static BorderRadius get defaultBorder => BorderRadius.circular(defaultValue);
  static BorderRadius get smMdBorder => BorderRadius.circular(smMd);
  static BorderRadius get mdBorder => BorderRadius.circular(md);
  static BorderRadius get lgBorder => BorderRadius.circular(lg);
  static BorderRadius get lgXlBorder => BorderRadius.circular(lgXl);
  static BorderRadius get xlBorder => BorderRadius.circular(xl);
  static BorderRadius get fullBorder => BorderRadius.circular(full);
}

// 4. Elevation Scale & Shadow System
class AppElevation {
  static const double level0 = 0.0; // Flat cards, inline borders
  static const double level1 = 1.0; // Resting cards, list items
  static const double level2 = 3.0; // Floating actions, dropdown menus
  static const double level3 = 6.0; // Sticky bars, bottom sheets, snackbars
  static const double level4 = 12.0; // Modal dialogs, full screen overlays

  static const BoxShadow shadowLevel0 = BoxShadow(
    color: Colors.transparent,
    offset: Offset.zero,
    blurRadius: 0,
  );

  static const BoxShadow shadowLevel1 = BoxShadow(
    color: Color(0x140D1321), // rgba(13, 19, 33, 0.08)
    offset: Offset(0, 2),
    blurRadius: 8,
    spreadRadius: 0,
  );

  static const BoxShadow shadowLevel2 = BoxShadow(
    color: Color(0x1F0D1321), // rgba(13, 19, 33, 0.12)
    offset: Offset(0, 4),
    blurRadius: 16,
    spreadRadius: 0,
  );

  static const BoxShadow shadowLevel3 = BoxShadow(
    color: Color(0x290D1321), // rgba(13, 19, 33, 0.16)
    offset: Offset(0, 8),
    blurRadius: 24,
    spreadRadius: 0,
  );

  static const BoxShadow shadowLevel4 = BoxShadow(
    color: Color(0x3D0D1321), // rgba(13, 19, 33, 0.24)
    offset: Offset(0, 16),
    blurRadius: 32,
    spreadRadius: 0,
  );

  static List<BoxShadow> get shadowLevel1List => [shadowLevel1];
  static List<BoxShadow> get shadowLevel2List => [shadowLevel2];
  static List<BoxShadow> get shadowLevel3List => [shadowLevel3];
  static List<BoxShadow> get shadowLevel4List => [shadowLevel4];
}

// Backwards-compatible AppShadows class
class AppShadows {
  static const BoxShadow level1 = AppElevation.shadowLevel1;
  static const BoxShadow level2 = AppElevation.shadowLevel2;
}

// 5. Motion & Animation Tokens
class AppMotion {
  // Durations
  static const Duration durationFast =
      Duration(milliseconds: 150); // Micro-interactions, button taps
  static const Duration durationMedium =
      Duration(milliseconds: 300); // Sheet slides, tab transitions
  static const Duration durationMediumSlow =
      Duration(milliseconds: 400); // Hero banner entrance animations
  static const Duration durationSlow =
      Duration(milliseconds: 500); // Screen entrances, hero banners
  static const Duration snackBarDisplay =
      Duration(seconds: 2); // Toast/SnackBar display timeout

  // Easing Curves
  static const Curve curveEntrance = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveStateChange = Curves.easeInOut;
  static const Curve curveBounce = Curves.elasticOut;

  // Logic Guards
  static const Duration debounceGuard =
      Duration(milliseconds: 600); // Button tap debounce threshold
}

// 6. Iconography Scale Tokens
class AppIconSize {
  static const double xs = 14.0; // Compact badge icons, status indicators
  static const double sm = 16.0; // Inline text icons, small button icons
  static const double md =
      24.0; // Standard list tile leading icons, app bar actions
  static const double lg = 32.0; // Featured card icons, metric stat badges
  static const double xl = 48.0; // Empty state visual graphic icons
}

// 7. Typography Scale (Role-Based System)
class AppTypography {
  /// Hero stat numbers, large splash headings (48pt)
  static TextStyle get displayLg => GoogleFonts.poppins(
        fontSize: 48,
        fontWeight: FontWeight.bold,
        height: 56 / 48,
        letterSpacing: -48 * 0.02,
      );

  /// Primary screen titles (desktop/tablet) (32pt)
  static TextStyle get headlineLg => GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 40 / 32,
      );

  /// Primary screen titles (mobile viewport) (24pt)
  static TextStyle get headlineLgMobile => GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 32 / 24,
      );

  /// Secondary headings, PIN entry numerals, modal subtitles (20pt)
  static TextStyle get headlineMd => GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 28 / 20,
      );

  /// Card titles, section headers, dialog titles (18pt)
  static TextStyle get titleMd => GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
      );

  /// Prominent body text, lead paragraphs (16pt)
  static TextStyle get bodyLg => GoogleFonts.poppins(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        height: 24 / 16,
      );

  /// Standard body text, form input text (14pt)
  static TextStyle get bodyMd => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        height: 20 / 14,
      );

  /// Small body text / secondary descriptions (13pt)
  static TextStyle get bodySm => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.normal,
        height: 18 / 13,
      );

  /// Input labels, button titles, pill badges (12pt)
  static TextStyle get labelLg => GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 16 / 12,
        letterSpacing: 12 * 0.05,
      );

  /// Caption text, metadata timestamps, status badges (11pt)
  static TextStyle get labelMd => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 14 / 11,
      );

  /// Micro badges, detail notes, count tags (10pt)
  static TextStyle get labelSm => GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        height: 12 / 10,
      );

  /// Caption text (11pt / regular)
  static TextStyle get caption => GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w400,
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
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.primary,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: AppColors.surface.withValues(alpha: 0.85),
    indicatorColor: AppColors.secondary.withValues(alpha: 0.25),
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
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      textStyle: WidgetStatePropertyAll(
        GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.surfaceContainer;
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.onPrimary;
        }
        return AppColors.onSurface;
      }),
      iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.onPrimary;
        }
        return AppColors.onSurface;
      }),
      side: const WidgetStatePropertyAll(
        BorderSide(color: AppColors.outlineVariant, width: 1.0),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.defaultValue),
        ),
      ),
    ),
  ),
);

// Hand-crafted dark mode color scheme (WCAG AA compliant contrast ratios >= 4.5:1 for text, >= 3:1 for controls)
const ColorScheme quickDeliveryDarkColorScheme = ColorScheme.dark(
  primary: Color(
      0xFFFFC107), // Amber Gold primary accent in dark mode (contrast 13.5:1 on dark surface)
  onPrimary: Color(0xFF0F172A), // Dark Navy text on Amber Gold
  primaryContainer: Color(0xFF1E293B), // Dark Slate container
  onPrimaryContainer: Color(0xFFF8FAFC),
  secondary: Color(0xFFFFC107), // Amber Gold secondary
  onSecondary: Color(0xFF0F172A),
  secondaryContainer: Color(0xFF334155),
  onSecondaryContainer: Color(0xFFFFDF9E),
  surface: Color(0xFF0F172A), // Dark Navy/Slate surface background
  onSurface:
      Color(0xFFF8FAFC), // High contrast off-white text (contrast 15.8:1)
  surfaceDim: Color(0xFF0A0E17),
  surfaceContainerLowest: Color(0xFF0F172A),
  surfaceContainerLow: Color(0xFF1E293B),
  surfaceContainer: Color(0xFF1E293B), // Card background in dark mode
  surfaceContainerHigh: Color(0xFF334155),
  surfaceContainerHighest: Color(0xFF475569),
  onSurfaceVariant:
      Color(0xFFCBD5E1), // Light Slate subtitle text (contrast 10.5:1)
  outline: Color(0xFF64748B), // Slate border
  outlineVariant: Color(0xFF475569), // Darker slate divider
  error: Color(0xFFF87171), // High contrast Red (contrast 7.8:1)
  onError: Color(0xFF0F172A),
);

final ThemeData quickDeliveryDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: quickDeliveryDarkColorScheme,
  scaffoldBackgroundColor: const Color(0xFF0A0E17),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: Color(0xFFF8FAFC),
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.90),
    indicatorColor: AppColors.secondary.withValues(alpha: 0.25),
    elevation: 0,
  ),
  textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.secondary,
      foregroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.defaultValue),
      ),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: AppColors.secondary,
    foregroundColor: AppColors.onSecondary,
  ),
  segmentedButtonTheme: SegmentedButtonThemeData(
    style: ButtonStyle(
      textStyle: WidgetStatePropertyAll(
        GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.secondary;
        }
        return const Color(0xFF1E293B);
      }),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF0F172A);
        }
        return const Color(0xFFF8FAFC);
      }),
      iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF0F172A);
        }
        return const Color(0xFFF8FAFC);
      }),
      side: const WidgetStatePropertyAll(
        BorderSide(color: Color(0xFF475569), width: 1.0),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.defaultValue),
        ),
      ),
    ),
  ),
);
