import 'package:flutter/material.dart';

/// Redesign A design tokens (FE-DS). Source of truth for the values:
/// docs/design/DESIGN_SYSTEM.md. Components in `lib/ui/components/` read
/// colors through [QdColors.of]; the app theme (main.dart: qdLightTheme /
/// qdDarkTheme) carries them as a theme extension.

/// Bundled font family name (pubspec.yaml `fonts:`), never fetched at runtime.
const String kQdFontFamily = 'IBMPlexSansArabic';

/// Spacing scale 4 / 8 / 12 / 16 / 20 / 24.
abstract final class QdSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;

  /// Horizontal screen padding used by every mockup.
  static const double gutter = x5;
}

/// Corner radii.
abstract final class QdRadius {
  /// Inputs, small buttons, icon tiles.
  static const double sm = 12;

  /// Primary button, banners.
  static const double button = 14;

  /// Cards and list groups.
  static const double card = 16;

  /// Top corners of a bottom sheet.
  static const double sheet = 24;

  /// Chips.
  static const double pill = 999;
}

/// Minimum interactive sizes.
abstract final class QdSize {
  static const double minTouch = 48;
  static const double buttonHeight = 54;
  static const double buttonHeightSm = 44;
  static const double fieldHeight = 52;
  static const double listRow = 52;
  static const double iconTile = 40;
  static const double iconTileLg = 48;
  static const double icon = 20;
  static const double iconLg = 24;
}

/// Color tokens. Two instances: [light] (the approved look) and [dark]
/// (navy surfaces, same gold rules; defined but not wired in FE-DS).
@immutable
class QdColors extends ThemeExtension<QdColors> {
  const QdColors({
    required this.surface,
    required this.fillSubtle,
    required this.fillMuted,
    required this.border,
    required this.borderInput,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.decorative,
    required this.gold,
    required this.onGold,
    required this.goldTint,
    required this.navy,
    required this.onNavy,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.neutral,
    required this.neutralBg,
    required this.disabledFill,
    required this.scrim,
  });

  final Color surface;
  final Color fillSubtle;
  final Color fillMuted;
  final Color border;
  final Color borderInput;
  final Color textPrimary;
  final Color textSecondary;

  /// Strike-through old prices only, never readable copy.
  final Color textMuted;

  /// Decorative marks only (upcoming timeline dot).
  final Color decorative;
  final Color gold;
  final Color onGold;
  final Color goldTint;
  final Color navy;
  final Color onNavy;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color danger;
  final Color dangerBg;
  final Color neutral;
  final Color neutralBg;
  final Color disabledFill;
  final Color scrim;

  static const QdColors light = QdColors(
    surface: Color(0xFFFFFFFF),
    fillSubtle: Color(0xFFF9FAFB),
    fillMuted: Color(0xFFF3F4F6),
    border: Color(0xFFE5E7EB),
    borderInput: Color(0xFFD1D5DB),
    textPrimary: Color(0xFF0D1321),
    textSecondary: Color(0xFF4B5563),
    textMuted: Color(0xFF6B7280),
    decorative: Color(0xFF9CA3AF),
    gold: Color(0xFFFFC107),
    onGold: Color(0xFF0D1321),
    goldTint: Color(0xFFFFF8E1),
    navy: Color(0xFF0D1321),
    onNavy: Color(0xFFFFC107),
    success: Color(0xFF15803D),
    successBg: Color(0xFFDCFCE7),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFFEF3C7),
    danger: Color(0xFFBA1A1A),
    dangerBg: Color(0xFFFEE2E2),
    neutral: Color(0xFF374151),
    neutralBg: Color(0xFFF3F4F6),
    disabledFill: Color(0xFFE5E7EB),
    scrim: Color(0x660D1321),
  );

  static const QdColors dark = QdColors(
    surface: Color(0xFF0D1321),
    fillSubtle: Color(0xFF161D2E),
    fillMuted: Color(0xFF1F2738),
    border: Color(0xFF273047),
    borderInput: Color(0xFF3A4560),
    textPrimary: Color(0xFFF9FAFB),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF9CA3AF),
    decorative: Color(0xFF6B7280),
    gold: Color(0xFFFFC107),
    onGold: Color(0xFF0D1321),
    goldTint: Color(0xFF3A2E0A),
    navy: Color(0xFFF9FAFB),
    onNavy: Color(0xFF0D1321),
    success: Color(0xFF86EFAC),
    successBg: Color(0xFF14532D),
    warning: Color(0xFFFCD34D),
    warningBg: Color(0xFF78350F),
    danger: Color(0xFFFCA5A5),
    dangerBg: Color(0xFF7F1D1D),
    neutral: Color(0xFFD1D5DB),
    neutralBg: Color(0xFF273047),
    disabledFill: Color(0xFF273047),
    scrim: Color(0x99000000),
  );

  /// The tokens of the nearest theme, or [light] when the theme does not
  /// carry the extension (a bare test app).
  static QdColors of(BuildContext context) =>
      Theme.of(context).extension<QdColors>() ?? light;

  @override
  QdColors copyWith({
    Color? surface,
    Color? fillSubtle,
    Color? fillMuted,
    Color? border,
    Color? borderInput,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? decorative,
    Color? gold,
    Color? onGold,
    Color? goldTint,
    Color? navy,
    Color? onNavy,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? danger,
    Color? dangerBg,
    Color? neutral,
    Color? neutralBg,
    Color? disabledFill,
    Color? scrim,
  }) {
    return QdColors(
      surface: surface ?? this.surface,
      fillSubtle: fillSubtle ?? this.fillSubtle,
      fillMuted: fillMuted ?? this.fillMuted,
      border: border ?? this.border,
      borderInput: borderInput ?? this.borderInput,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      decorative: decorative ?? this.decorative,
      gold: gold ?? this.gold,
      onGold: onGold ?? this.onGold,
      goldTint: goldTint ?? this.goldTint,
      navy: navy ?? this.navy,
      onNavy: onNavy ?? this.onNavy,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      neutral: neutral ?? this.neutral,
      neutralBg: neutralBg ?? this.neutralBg,
      disabledFill: disabledFill ?? this.disabledFill,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  QdColors lerp(ThemeExtension<QdColors>? other, double t) {
    if (other is! QdColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return QdColors(
      surface: l(surface, other.surface),
      fillSubtle: l(fillSubtle, other.fillSubtle),
      fillMuted: l(fillMuted, other.fillMuted),
      border: l(border, other.border),
      borderInput: l(borderInput, other.borderInput),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      decorative: l(decorative, other.decorative),
      gold: l(gold, other.gold),
      onGold: l(onGold, other.onGold),
      goldTint: l(goldTint, other.goldTint),
      navy: l(navy, other.navy),
      onNavy: l(onNavy, other.onNavy),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
      warning: l(warning, other.warning),
      warningBg: l(warningBg, other.warningBg),
      danger: l(danger, other.danger),
      dangerBg: l(dangerBg, other.dangerBg),
      neutral: l(neutral, other.neutral),
      neutralBg: l(neutralBg, other.neutralBg),
      disabledFill: l(disabledFill, other.disabledFill),
      scrim: l(scrim, other.scrim),
    );
  }
}

/// Type scale. Styles carry family, size, weight and height but no color:
/// components apply a [QdColors] color with `copyWith`.
abstract final class QdText {
  static const double _height = 1.4;

  static const TextStyle _base = TextStyle(
    fontFamily: kQdFontFamily,
    height: _height,
    letterSpacing: 0,
  );

  /// Auth screen title (A-Login, A-Signup).
  static final TextStyle screenTitleLg =
      _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700);

  /// Tab-root screen title.
  static final TextStyle screenTitle =
      _base.copyWith(fontSize: 26, fontWeight: FontWeight.w700);

  /// Sheet title and state hero title.
  static final TextStyle sheetTitle =
      _base.copyWith(fontSize: 22, fontWeight: FontWeight.w700);

  /// App-bar title on pushed screens, section title on dashboards.
  static final TextStyle header =
      _base.copyWith(fontSize: 18, fontWeight: FontWeight.w700);

  static final TextStyle rowTitle =
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600);

  static final TextStyle rowTitleSm =
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600);

  static final TextStyle body =
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400);

  static final TextStyle bodyStrong =
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  static final TextStyle secondary =
      _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400);

  static final TextStyle caption =
      _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400);

  static final TextStyle chip =
      _base.copyWith(fontSize: 12, fontWeight: FontWeight.w600);

  static final TextStyle button =
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700);

  static final TextStyle buttonSm =
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600);

  static final TextStyle amountLg =
      _base.copyWith(fontSize: 24, fontWeight: FontWeight.w700);
}
