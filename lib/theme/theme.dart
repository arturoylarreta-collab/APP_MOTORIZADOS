import 'package:flutter/material.dart';

class VenduColors {
  static const Color negro = Color(0xFF0E1117);
  static const Color negroSuave = Color(0xFF161922);
  static const Color amarillo = Color(0xFFF5B800);
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color gris = Color(0xFF9CA3AF);
  static const Color verde = Color(0xFF35C759);
  static const Color rojo = Color(0xFFFF453A);
  static const Color borde = Color(0xFF262B36);
}

ThemeData venduTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: VenduColors.negro,
    colorScheme: base.colorScheme.copyWith(
      primary: VenduColors.amarillo,
      onPrimary: VenduColors.negro,
      surface: VenduColors.negroSuave,
      error: VenduColors.rojo,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VenduColors.negro,
      foregroundColor: VenduColors.blanco,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: VenduColors.blanco,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VenduColors.negroSuave,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: VenduColors.gris),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VenduColors.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VenduColors.amarillo, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VenduColors.amarillo,
        foregroundColor: VenduColors.negro,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: VenduColors.amarillo),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: VenduColors.negroSuave,
      contentTextStyle: TextStyle(color: VenduColors.blanco),
      behavior: SnackBarBehavior.floating,
    ),
  );
}