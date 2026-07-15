import 'package:flutter/material.dart';

/// Centralized design tokens for the new GlovoMate design language.
///
/// RATIONALE: All screens (splash, group, map, chat, blacklist, settings,
/// member-detail, alert-composer, notifications) should pull colors, radii
/// and shadows from this file. No hardcoded hex anywhere else.
///
/// To rebrand later, change values here only — every screen updates
/// automatically via the [AppPalette] static helpers.
class AppColors {
  AppColors._();

  // ──────────── Brand ────────────
  static const Color indigo50 = Color(0xFFEEF0FF);
  static const Color indigo100 = Color(0xFFD9DEFF);
  static const Color indigo200 = Color(0xFFB3B9FF);
  static const Color indigo300 = Color(0xFF8C95FF);
  static const Color indigo400 = Color(0xFF6670FF);
  static const Color indigo500 = Color(0xFF5B6CFF);
  static const Color indigo600 = Color(0xFF4A56E6);
  static const Color indigo700 = Color(0xFF3940CC);
  static const Color indigo800 = Color(0xFF272DA0);
  static const Color indigo900 = Color(0xFF161B73);

  static const Color orange500 = Color(0xFFFF7A45);
  static const Color orange600 = Color(0xFFF25A1F);

  static const Color mint500 = Color(0xFF00D4A0);
  static const Color rose500 = Color(0xFFFF4D6D);
  static const Color amber500 = Color(0xFFFFB627);
  static const Color purple500 = Color(0xFF8E24AA);
  static const Color cyan500 = Color(0xFF00ACC1);

  // ──────────── Neutral ────────────
  static const Color ink900 = Color(0xFF0B0E1E);
  static const Color ink800 = Color(0xFF1A1F35);
  static const Color ink700 = Color(0xFF2A304B);
  static const Color ink500 = Color(0xFF5A6180);
  static const Color ink400 = Color(0xFF828AA8);
  static const Color ink300 = Color(0xFFB7BCD1);
  static const Color ink200 = Color(0xFFDDE0EE);
  static const Color ink100 = Color(0xFFEFF1F8);
  static const Color ink50 = Color(0xFFF7F8FC);

  // ──────────── Surfaces ────────────
  static const Color background = Color(0xFFF4F5FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDim = Color(0xFFF7F8FC);
  static const Color glassLight = Color(0xB3FFFFFF); // 70% white
  static const Color glassDark = Color(0xB3000000); // 70% black

  // ──────────── Semantic ────────────
  static const Color success = mint500;
  static const Color danger = rose500;
  static const Color warning = amber500;
  static const Color info = indigo500;

  // ──────────── Gradients ────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [indigo600, indigo500],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [indigo800, indigo500, indigo300],
  );
  static const LinearGradient dangerGradient = LinearGradient(
    colors: [rose500, Color(0xFFC73050)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient successGradient = LinearGradient(
    colors: [mint500, Color(0xFF00A37B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ──────────── Shadow tokens ────────────
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x1A5B6CFF), // 10% indigo
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1F5B6CFF), // 12% indigo
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x2E161B73), // 18% indigo900
      blurRadius: 60,
      offset: Offset(0, 24),
    ),
  ];
  static const List<BoxShadow> shadowGlowPrimary = [
    BoxShadow(
      color: Color(0x4D5B6CFF), // 30% indigo
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> shadowGlowOrange = [
    BoxShadow(
      color: Color(0x4DFF7A45), // 30% orange
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
  static const List<BoxShadow> shadowGlowDanger = [
    BoxShadow(
      color: Color(0x4DFF4D6D), // 30% rose
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}

/// Convenience accessor so callers can write `AppPalette.bg` etc.
class AppPalette {
  AppPalette._();

  // Brand
  static const Color primary = AppColors.indigo500;
  static const Color primaryDark = AppColors.indigo700;
  static const Color accent = AppColors.orange500;

  // Backgrounds
  static const Color bg = AppColors.background;
  static const Color card = AppColors.surface;
  static const Color textPrimary = AppColors.ink900;
  static const Color textSecondary = AppColors.ink500;
  static const Color textMuted = AppColors.ink400;
  static const Color border = AppColors.ink200;
  static const Color divider = AppColors.ink100;

  // Status
  static const Color success = AppColors.success;
  static const Color danger = AppColors.danger;
  static const Color warning = AppColors.warning;
  static const Color info = AppColors.info;

  // Gradients
  static const LinearGradient primaryGradient = AppColors.primaryGradient;
  static const LinearGradient splashGradient = AppColors.splashGradient;
  static const LinearGradient dangerGradient = AppColors.dangerGradient;
  static const LinearGradient successGradient = AppColors.successGradient;
}
