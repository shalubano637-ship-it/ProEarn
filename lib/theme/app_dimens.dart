
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

class AppRadius {
  AppRadius._();

  static const double sm = 12; // chips and compact controls
  static const double md = 20; // cards and tiles
  static const double lg = 24; // sheets and dialogs, larger cards
  static const double xl = 28; // hero cards and modals
  static const double pill = 999; // fully rounded (avatars fallback, tags)

  static const BorderRadius smRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlRadius = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillRadius = BorderRadius.all(Radius.circular(pill));
}

class AppIconSize {
  AppIconSize._();

  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
}

class AppElevation {
  AppElevation._();

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x55FFFFFF), blurRadius: 8, offset: Offset(-3, -3)),
    BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: Offset(5, 6)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x66FFFFFF), blurRadius: 10, offset: Offset(-4, -4)),
    BoxShadow(color: AppColors.shadow, blurRadius: 22, offset: Offset(7, 8)),
  ];

  static const List<BoxShadow> accentGlow = [
    BoxShadow(color: Color(0x40D4AF37), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
