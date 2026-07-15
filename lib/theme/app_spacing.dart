/// Spacing, radius and sizing tokens. Use these everywhere instead of
/// hard-coded pixel values so the design system stays consistent.
class AppSpacing {
  AppSpacing._();

  // 4pt base grid
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double mega = 56;

  // Page-level
  static const double pagePadding = 20;
  static const double pagePaddingTight = 16;
  static const double sectionGap = 24;

  // Component sizes
  static const double buttonHeight = 56;
  static const double buttonHeightSm = 44;
  static const double inputHeight = 56;
  static const double iconButton = 40;
  static const double iconButtonSm = 32;
  static const double fab = 56;
  static const double appBar = 56;
  static const double bottomNav = 68;
  static const double statusBar = 44;
}

/// Border-radius tokens.
class AppRadius {
  AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 28;
  static const double full = 9999;

  // Common composites
  static const double card = lg;
  static const double button = md;
  static const double input = md;
  static const double chip = full;
  static const double sheet = xxl;
  static const double sheetTop = 28;
}

/// Icon-size tokens.
class AppIcon {
  AppIcon._();

  static const double xs = 14;
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
  static const double xl = 36;
  static const double xxl = 48;
}
