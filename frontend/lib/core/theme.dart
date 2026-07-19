import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Brand color palette definitions
const Color kBrandNavy = Color(0xFF0D1321);
const Color kBrandGold = Color(0xFFFFC107);
const Color kBrandLightGray = Color(0xFFE5E7EB);
const Color kBrandWhite = Color(0xFFFFFFFF);

// Status colors (distinct from Amber Gold brand accent)
const Color kStatusSuccess = Color(0xFF00E676);
const Color kStatusDanger = Color(0xFFFF1744);
const Color kStatusWarning = Color(0xFFFF7A00);

final ThemeData quickDeliveryTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme(
    brightness: Brightness.light,
    primary: kBrandNavy,
    onPrimary: Colors.white,
    secondary: kBrandGold,
    onSecondary: kBrandNavy, // dark contrast text on amber gold
    error: kStatusDanger,
    onError: Colors.white,
    surface: kBrandWhite,
    onSurface: kBrandNavy,
  ),
  scaffoldBackgroundColor: kBrandLightGray,
  appBarTheme: const AppBarTheme(
    backgroundColor: kBrandNavy,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  textTheme: GoogleFonts.poppinsTextTheme(),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kBrandNavy,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: kBrandGold,
    foregroundColor: kBrandNavy,
  ),
);

final ColorScheme _darkBaseScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF0D1321),
  brightness: Brightness.dark,
);

final ThemeData quickDeliveryDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: _darkBaseScheme.copyWith(
    secondary: kBrandGold,
    onSecondary: kBrandNavy,
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
      backgroundColor: kBrandNavy,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: kBrandGold,
    foregroundColor: kBrandNavy,
  ),
);
