import 'package:flutter/material.dart';

/// Palette industrielle. Vert/orange/rouge réservés aux STATUTS uniquement.
class AppColors {
  static const navy = Color(0xFF12263F);
  static const navyLight = Color(0xFF1A3250);
  static const navyBorder = Color(0xFF3A5373);
  static const steel = Color(0xFF1F4E79);
  static const bg = Color(0xFFF1F4F8);
  static const border = Color(0xFFD5DBE3);
  static const divider = Color(0xFFE3E8EE);
  static const ink = Color(0xFF0F1B2D);
  static const muted = Color(0xFF556070);

  static const ok = Color(0xFF2F855A);
  static const okText = Color(0xFF166534);
  static const okBg = Color(0xFFD9F0E1);
  static const warn = Color(0xFFD97706);
  static const warnText = Color(0xFF6B3A00);
  static const warnBg = Color(0xFFFDE8D0);
  static const danger = Color(0xFFB42318);
  static const infoText = Color(0xFF12365A);
  static const infoBg = Color(0xFFDCE8F5);
}

ThemeData buildAppTheme() {
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.steel,
    ).copyWith(primary: AppColors.steel, onPrimary: Colors.white),
    scaffoldBackgroundColor: AppColors.bg,
    dividerColor: AppColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.steel,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.steel,
        minimumSize: const Size(0, 44),
        shape: shape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.steel,
        side: const BorderSide(color: AppColors.steel),
        minimumSize: const Size(0, 44),
        shape: shape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.infoBg,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.steel
              : AppColors.muted,
        ),
      ),
    ),
  );
}
