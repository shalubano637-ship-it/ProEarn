// ============================================================================
// APP TEXT STYLES — single source of truth for typography.
//
// The app previously used 13 different ad-hoc font sizes and inconsistent
// weights scattered across files. This collapses that into a clean scale.
//
// HOW TO USE:
//   Text('Hello', style: AppTextStyles.bodyMedium)
//   Text('₹120', style: AppTextStyles.h2.copyWith(color: AppColors.accent))
//
// Colors are intentionally NOT baked into most styles (default = current
// theme's textPrimary via Theme.of(context)) — pass color per-usage, or use
// AppTextStyles.withColor(style, color).
// ============================================================================

import 'package:flutter/material.dart';

class AppTextStyles {
  AppTextStyles._();

  static const String? _fontFamily = null; // using platform default; swap here to re-brand fonts app-wide

  // Display — splash / big empty states / earnings hero numbers
  static const TextStyle displayLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 38,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    height: 1.15,
  );

  // Headings — page titles, section headers
  static const TextStyle h1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle bodyRegular = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  // Labels / buttons
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  // Captions / meta text / timestamps
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  static const TextStyle captionBold = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle overline = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0.5,
  );

  // Special — big money/number displays (wallet balance, earnings)
  static const TextStyle numericHero = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w900,
    letterSpacing: -1,
    height: 1.0,
  );

  /// Helper to quickly re-tint a style without repeating `.copyWith` everywhere.
  static TextStyle withColor(TextStyle style, Color color) => style.copyWith(color: color);
}
