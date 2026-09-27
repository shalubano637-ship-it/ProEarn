
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color accent = Color(0xFFD4AF37); // premium gold
  static const Color accentMuted = Color(0xFF9C7F2B); // dimmer gold (disabled/secondary)
  static const Color accentSoft = Color(0x33D4AF37); // gold @ 20% — chips/badges bg

  static const List<Color> accentGradient = [Color(0xFFF4D976), Color(0xFFD4AF37), Color(0xFF9C7F2B)];

  static const Color background = Color(0xFF0A0A0A); // app background — near-true-black
  static const Color surface = Color(0xFF141414); // cards, sheets, dialogs
  static const Color surfaceElevated = Color(0xFF1E1E1E); // raised surfaces (modals over cards)
  static const Color surfaceHighlight = Color(0xFF262626); // pressed/hover/selected surface
  static const Color divider = Color(0xFF2A2A2A);
  static const Color border = Color(0xFF2F2F2F);

  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF3F3F3);
  static const Color surfaceHighlightLight = Color(0xFFEBEBEB);
  static const Color dividerLight = Color(0xFFE2E2E2);
  static const Color borderLight = Color(0xFFE0E0E0);

  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFAFAFAF);
  static const Color textTertiary = Color(0xFF737373);
  static const Color textDisabled = Color(0xFF4D4D4D);
  static const Color textOnAccent = Color(0xFF0A0A0A); // text placed on top of gold

  static const Color textPrimaryLight = Color(0xFF121212);
  static const Color textSecondaryLight = Color(0xFF5C5C5C);
  static const Color textTertiaryLight = Color(0xFF8A8A8A);
  static const Color textDisabledLight = Color(0xFFBDBDBD);

  static const Color success = Color(0xFF2ECC71);
  static const Color successSoft = Color(0x332ECC71);
  static const Color warning = Color(0xFFF5A623);
  static const Color warningSoft = Color(0x33F5A623);
  static const Color error = Color(0xFFE84C4C);
  static const Color errorSoft = Color(0x33E84C4C);
  static const Color info = Color(0xFF4A9DE0);
  static const Color infoSoft = Color(0x334A9DE0);

  static const Color overlay = Color(0x99000000); // scrims over images/videos
  static const Color shimmerBase = Color(0xFF1A1A1A);
  static const Color shimmerHighlight = Color(0xFF2C2C2C);
  static const Color shadow = Color(0x66000000);
  static const Color transparent = Colors.transparent;

  static const Color verified = Color(0xFF4A9DE0);
  static const Color online = Color(0xFF2ECC71);

  static const Color silver = Color(0xFFC0C8D6); // rank #2
  static const Color bronze = Color(0xFFCD8A5A); // rank #3
}
