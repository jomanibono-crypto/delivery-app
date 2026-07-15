import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Typography tokens. Pair Plus Jakarta Sans (display, weight 700-800) for
/// headlines with the system font for body text. All sizes follow an
/// 8pt scale and are designed to render crisply on iOS / Android devices
/// from 360dp up.
class AppTypography {
  AppTypography._();

  static const String _displayFont = 'Plus Jakarta Sans';
  static const String _bodyFont = 'Cairo';

  // ──────────── Display (headlines / titles) ────────────
  static const TextStyle displayLg = TextStyle(
    fontFamily: _displayFont,
    fontSize: 42,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1.0,
    color: AppColors.ink900,
  );

  static const TextStyle displayMd = TextStyle(
    fontFamily: _displayFont,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.8,
    color: AppColors.ink900,
  );

  static const TextStyle displaySm = TextStyle(
    fontFamily: _displayFont,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
    color: AppColors.ink900,
  );

  // ──────────── Title (section / card titles) ────────────
  static const TextStyle titleLg = TextStyle(
    fontFamily: _displayFont,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.3,
    color: AppColors.ink900,
  );

  static const TextStyle titleMd = TextStyle(
    fontFamily: _displayFont,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.ink900,
  );

  static const TextStyle titleSm = TextStyle(
    fontFamily: _displayFont,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.ink900,
  );

  // ──────────── Body ────────────
  static const TextStyle bodyLg = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.ink900,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.ink900,
  );

  static const TextStyle bodySm = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.ink500,
  );

  // ──────────── Label / Caption ────────────
  static const TextStyle labelLg = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink900,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink500,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink400,
    letterSpacing: 0.3,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink400,
  );

  // ──────────── Numeric (for stats) ────────────
  static const TextStyle numberXl = TextStyle(
    fontFamily: _displayFont,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.5,
  );

  static const TextStyle numberLg = TextStyle(
    fontFamily: _displayFont,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.0,
  );

  static const TextStyle numberMd = TextStyle(
    fontFamily: _displayFont,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  // ──────────── Button ────────────
  static const TextStyle buttonLg = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0.1,
  );

  static const TextStyle buttonMd = TextStyle(
    fontFamily: _bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );
}
