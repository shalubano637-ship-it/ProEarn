// ============================================================================
// APP THEME EXTENSION — carries brand/semantic tokens that Flutter's built-in
// ThemeData/ColorScheme has no slot for (gradients, success/warning/info,
// shimmer colors, glow shadows). Access anywhere via:
//
//   final ext = Theme.of(context).extension<AppThemeExtension>()!;
//   ext.accentGradient
//   ext.success
//
// This is what makes the theme swappable from ONE place: change the values
// in AppColors/AppDimens, and every screen that reads via the extension (or
// via ColorScheme) updates automatically — no per-screen edits needed.
// ============================================================================

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimens.dart';

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final List<Color> accentGradient;
  final Color accentSoft;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color infoSoft;
  final Color overlay;
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color verified;
  final Color online;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> raisedShadow;
  final List<BoxShadow> accentGlow;

  const AppThemeExtension({
    required this.accentGradient,
    required this.accentSoft,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
    required this.overlay,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.verified,
    required this.online,
    required this.cardShadow,
    required this.raisedShadow,
    required this.accentGlow,
  });

  static const AppThemeExtension dark = AppThemeExtension(
    accentGradient: AppColors.accentGradient,
    accentSoft: AppColors.accentSoft,
    success: AppColors.success,
    successSoft: AppColors.successSoft,
    warning: AppColors.warning,
    warningSoft: AppColors.warningSoft,
    error: AppColors.error,
    errorSoft: AppColors.errorSoft,
    info: AppColors.info,
    infoSoft: AppColors.infoSoft,
    overlay: AppColors.overlay,
    shimmerBase: AppColors.shimmerBase,
    shimmerHighlight: AppColors.shimmerHighlight,
    verified: AppColors.verified,
    online: AppColors.online,
    cardShadow: AppElevation.card,
    raisedShadow: AppElevation.raised,
    accentGlow: AppElevation.accentGlow,
  );

  // Light mode reuses the same semantic/brand colors — only surfaces/text
  // differ, and those are handled by ColorScheme, not this extension.
  static const AppThemeExtension light = dark;

  @override
  AppThemeExtension copyWith({
    List<Color>? accentGradient,
    Color? accentSoft,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
    Color? info,
    Color? infoSoft,
    Color? overlay,
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? verified,
    Color? online,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? raisedShadow,
    List<BoxShadow>? accentGlow,
  }) {
    return AppThemeExtension(
      accentGradient: accentGradient ?? this.accentGradient,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      overlay: overlay ?? this.overlay,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      verified: verified ?? this.verified,
      online: online ?? this.online,
      cardShadow: cardShadow ?? this.cardShadow,
      raisedShadow: raisedShadow ?? this.raisedShadow,
      accentGlow: accentGlow ?? this.accentGlow,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    // Colors here are treated as fixed brand tokens rather than animated
    // between light/dark, so we simply switch at t >= 0.5.
    return t < 0.5 ? this : other;
  }
}

/// Convenience getter: `context.appColors.success`
extension AppThemeExtensionContext on BuildContext {
  AppThemeExtension get appColors =>
      Theme.of(this).extension<AppThemeExtension>() ?? AppThemeExtension.dark;
}
