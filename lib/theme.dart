import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF565E74);
  static const Color primaryContainer = Color(0xFFDAE2FD);
  static const Color onPrimary = Color(0xFFF7F7FF);
  static const Color onPrimaryContainer = Color(0xFF4A5167);

  static const Color secondary = Color(0xFF526074);
  static const Color secondaryContainer = Color(0xFFD5E3FC);
  
  static const Color background = Color(0xFFF7F9FB);
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceContainerLow = Color(0xFFF0F4F7);
  static const Color surfaceContainerHighest = Color(0xFFD9E4EA);
  static const Color surfaceVariant = Color(0xFFD9E4EA);

  static const Color onSurface = Color(0xFF2A3439);
  static const Color onSurfaceVariant = Color(0xFF566166);
  
  static const double borderRadius = 12.0;
  static const Color tertiary = Color(0xFF006787);
  static const Color tertiaryContainer = Color(0xFF7BD1FA);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        onPrimary: onPrimary,
        secondary: secondary,
        secondaryContainer: secondaryContainer,
        surface: surface,
        onSurface: onSurface,
        tertiary: tertiary,
        tertiaryContainer: tertiaryContainer,
      ),
      scaffoldBackgroundColor: background,
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontSize: 56, letterSpacing: -0.02, fontWeight: FontWeight.bold, color: onSurface),
        displayMedium: TextStyle(fontFamily: 'Inter', fontSize: 45, color: onSurface),
        displaySmall: TextStyle(fontFamily: 'Inter', fontSize: 36, color: onSurface),
        headlineLarge: TextStyle(fontFamily: 'Inter', fontSize: 32, fontWeight: FontWeight.w600, color: onSurface),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 28, color: onSurface),
        headlineSmall: TextStyle(fontFamily: 'Inter', fontSize: 24, color: onSurface),
        titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, color: onSurfaceVariant),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, color: onSurfaceVariant),
        labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.05, color: onSurfaceVariant),
        labelMedium: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.05, color: onSurfaceVariant),
      ),
    );
  }
}
