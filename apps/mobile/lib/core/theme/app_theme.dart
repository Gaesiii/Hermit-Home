// lib/core/theme/app_theme.dart
//
// Centralised Material 3 theme for Hermit-Home.
// Warm green primary (terrarium / nature) on a near-black dark surface.
// All screens import AppTheme.themeData directly from main.dart.

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Brand Palette ────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF4CAF82); // muted emerald
  static const Color primaryDark = Color(0xFF357A5A);
  static const Color accent = Color(0xFFE8A020); // amber — matches web
  static const Color bgDark = Color(0xFF0E1110); // near-black green tint
  static const Color surface = Color(0xFF161C19);
  static const Color surfaceVariant = Color(0xFF1E2822);
  static const Color onSurface = Color(0xFFD8E0DC);
  static const Color subtle = Color(0xFF4A5551);
  static const Color error = Color(0xFFE84040);

  // ── Theme Data ───────────────────────────────────────────────────────────────
  static ThemeData get themeData => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          onPrimary: Colors.black,
          secondary: accent,
          onSecondary: Colors.black,
          surface: surface,
          onSurface: onSurface,
          error: error,
          onError: Colors.white,
          surfaceContainerHighest: surfaceVariant,
        ),
        scaffoldBackgroundColor: bgDark,
        fontFamily: 'Roboto',

        // ── AppBar ──────────────────────────────────────────────────────────
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: onSurface,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: onSurface,
          ),
        ),

        // ── Input Fields ────────────────────────────────────────────────────
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceVariant,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2A3530), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: error, width: 1.5),
          ),
          labelStyle: const TextStyle(color: subtle, fontSize: 14),
          hintStyle: const TextStyle(color: subtle, fontSize: 14),
          errorStyle: const TextStyle(color: error, fontSize: 12),
          prefixIconColor: subtle,
          suffixIconColor: subtle,
        ),

        // ── Elevated Buttons ────────────────────────────────────────────────
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
            elevation: 0,
          ),
        ),

        // ── Text Buttons ────────────────────────────────────────────────────
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      );

  // ── Reusable helpers ─────────────────────────────────────────────────────────

  /// Consistent card decoration used on the auth & dashboard screens.
  static BoxDecoration cardDecoration({double radius = 16}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFF2A3530), width: 1),
      );
}
