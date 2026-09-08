import 'package:flutter/material.dart';

/// Colours carried over from the Wails frontend stylesheet so the Android app
/// keeps the same identity as the desktop build.
abstract final class AppColors {
  static const Color background = Color(0xFF222831);
  static const Color surface = Color(0xFF393E46);
  static const Color surfaceMuted = Color(0xFF1E1E1E);
  static const Color border = Color(0xFF444444);
  static const Color accent = Color(0xFF3366CC);
  static const Color accentLight = Color(0xFF5588DD);
  static const Color text = Color(0xFFE0E0E0);
  static const Color textStrong = Color(0xFFF0F0F0);
  static const Color textMuted = Color(0xFF9AA3AE);
  static const Color partOfSpeech = Color(0xFFA0CFFF);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accentLight,
      surface: AppColors.background,
      onSurface: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textStrong,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surfaceMuted,
      indicatorColor: AppColors.accent.withValues(alpha: 0.28),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.textStrong
              : AppColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.textStrong
              : AppColors.textMuted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      hintStyle: const TextStyle(color: Color(0xFF888888)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF66AAFF)),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.textStrong,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
