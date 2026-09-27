
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

  static const double sm = 8; // chips, small buttons, inputs
  static const double md = 12; // cards, tiles
  static const double lg = 16; // sheets, dialogs, larger cards
  static const double xl = 20; // hero cards, modals
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
    BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> accentGlow = [
    BoxShadow(color: Color(0x40D4AF37), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
