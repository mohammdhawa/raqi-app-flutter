import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Centralised theme. Cairo is applied via [GoogleFonts.cairoTextTheme]
/// which downloads and caches the font at runtime — no font files needed
/// in `assets/`.
class AppTheme {
  AppTheme._();

  // ── Typography helpers ─────────────────────────────────────────────
  // Each returns a standalone TextStyle so screens can use them directly:
  //   style: AppTheme.heading2()
  // All use Cairo via google_fonts.

  static TextStyle display({Color? color}) => GoogleFonts.cairo(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  static TextStyle heading1({Color? color}) => GoogleFonts.cairo(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  static TextStyle heading2({Color? color}) => GoogleFonts.cairo(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  static TextStyle heading3({Color? color}) => GoogleFonts.cairo(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  static TextStyle title({Color? color}) => GoogleFonts.cairo(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: color ?? AppColors.text,
      );

  static TextStyle labelL({Color? color}) => GoogleFonts.cairo(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: color ?? AppColors.text,
      );

  static TextStyle label({Color? color}) => GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.5,
        color: color ?? AppColors.text,
      );

  static TextStyle body({Color? color}) => GoogleFonts.cairo(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: color ?? AppColors.text,
      );

  static TextStyle bodyS({Color? color}) => GoogleFonts.cairo(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: color ?? AppColors.text,
      );

  static TextStyle caption({Color? color}) => GoogleFonts.cairo(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: color ?? AppColors.text,
      );

  static TextStyle captionS({Color? color}) => GoogleFonts.cairo(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color ?? AppColors.text,
      );

  static TextStyle micro({Color? color}) => GoogleFonts.cairo(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: color ?? AppColors.text,
      );

  // ── ThemeData ──────────────────────────────────────────────────────

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    final cairoText = GoogleFonts.cairoTextTheme(base.textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.textOnDark,
        secondary: AppColors.accent,
        onSecondary: Color(0xFF2A2010),
        tertiary: AppColors.accentSoft,
        surface: AppColors.bg,
        onSurface: AppColors.text,
        error: AppColors.rejected,
        onError: AppColors.textOnDark,
      ),
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: cairoText,
      primaryTextTheme: cairoText,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textOnDark,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.rMd),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: _outline(AppColors.border, width: 1.5),
        enabledBorder: _outline(AppColors.border, width: 1.5),
        focusedBorder: _outline(AppColors.primary, width: 1.5),
        errorBorder: _outline(AppColors.rejected, width: 1.5),
        focusedErrorBorder: _outline(AppColors.rejected, width: 1.5),
        labelStyle: GoogleFonts.cairo(
          color: AppColors.text2,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.cairo(
          color: AppColors.text3,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnDark,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.rLg),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.rLg),
          ),
          textStyle: GoogleFonts.cairo(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textOnDark,
        unselectedLabelColor: AppColors.textOnDark.withValues(alpha: 0.65),
        indicatorColor: AppColors.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.cairo(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnDark,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        labelStyle: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.pill),
        ),
      ),
    );
  }

  static OutlineInputBorder _outline(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.rLg),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}