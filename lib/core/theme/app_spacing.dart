/// 4-pt spacing scale and corner-radius scale for MedIntel Nexus.
///
/// The design language is consistently soft-cornered and breathes — these
/// tokens keep every screen on the same rhythm.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard horizontal screen gutter.
  static const double gutter = 20;
}

/// Corner-radius scale. Cards use [lg], sheets use [xl], pills are fully round.
abstract final class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

/// Motion tokens — durations and the curves used across the app.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}
