import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme modeled on Claude / Anthropic: warm ivory canvas, terracotta accent,
/// warm near-black ink, soft rounded surfaces. Serif headings (Source Serif 4,
/// echoing Tiempos/Copernicus) with a clean Inter sans for body and UI.
class AppTheme {
  // Brand palette
  static const Color coral = Color(0xFFD97757); // Claude terracotta accent
  static const Color coralDark = Color(0xFFBE5D3D);
  static const Color cream = Color(0xFFF0EEE6); // Anthropic ivory canvas
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sand = Color(0xFFEDE9DD); // subtle warm fill
  static const Color ink = Color(0xFF000000); // pure black text (max contrast)
  static const Color muted = Color(0xFF2A2926); // very dark secondary text
  static const Color border = Color(0xFFE5E1D5); // warm hairline
  static const double radius = 12;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: coral,
      brightness: Brightness.light,
    ).copyWith(
      primary: coral,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: sand,
      outline: border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
    );

    // Body/UI in Inter; large headings in a refined serif.
    final text = GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineSmall: GoogleFonts.sourceSerif4(
              fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),
          titleLarge: GoogleFonts.sourceSerif4(
              fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),
          titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: ink),
          bodyLarge: GoogleFonts.inter(height: 1.45, color: ink),
          bodyMedium: GoogleFonts.inter(height: 1.45, color: muted),
          labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600),
        );

    OutlineInputBorder inputBorder(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c, width: w),
        );

    final roundedShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.sourceSerif4(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: ink,
        ),
        iconTheme: const IconThemeData(color: ink),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder(border, 1),
        enabledBorder: inputBorder(border, 1),
        focusedBorder: inputBorder(coral, 1.6),
        labelStyle: GoogleFonts.inter(color: muted),
        floatingLabelStyle:
            GoogleFonts.inter(color: coralDark, fontWeight: FontWeight.w600),
        hintStyle: GoogleFonts.inter(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: coral,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: roundedShape,
          textStyle:
              GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: coral,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: roundedShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: border, width: 1.4),
          shape: roundedShape,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: coralDark),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: ink),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: coral,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: roundedShape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        surfaceTintColor: Colors.transparent,
        indicatorColor: coral.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? coralDark : muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? ink : muted)),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: sand,
        side: BorderSide.none,
        labelStyle: GoogleFonts.inter(
            fontSize: 12, fontWeight: FontWeight.w500, color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
