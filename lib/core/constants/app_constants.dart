/// App-wide constants — durations, sizes, storage keys.
abstract final class AppConstants {
  static const String appName = 'MedIntel Nexus';
  static const String appTagline =
      'AI-Powered Clinical Intelligence & Prescription Risk Analysis';

  // Splash
  static const Duration splashHold = Duration(milliseconds: 2200);

  // Secure-storage keys (session/identity — cleared on sign-out)
  static const String kOnboardingComplete = 'mn_onboarding_complete';
  // Cached projection of the signed-in user (so a cold boot restores the real
  // identity instead of a hardcoded placeholder).
  static const String kUserName = 'mn_user_name';

  // Layout
  static const double maxContentWidth = 1200;

  // Supported assistant languages (ISO codes)
  static const List<String> supportedLanguages = ['en', 'ta', 'hi'];
}

/// Responsive breakpoint thresholds (logical pixels).
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1024;
}

/// How wide a page's content is allowed to grow before it stops stretching
/// and starts centring instead.
///
/// A browser window is not a phone. Left unconstrained, every screen becomes
/// a 1900-pixel line of text over a 1900-pixel card — technically responsive,
/// unreadable in practice. These caps are the width the content is *designed*
/// for; past them the page gains margin, not column width.
abstract final class ContentWidth {
  /// Sign-in, sign-up and other single-column forms. Matches the bottom
  /// sheet's cap so a form looks the same whichever surface it arrives on.
  static const double form = 480;

  /// Reading and conversation columns — report bodies, assistant threads.
  /// Roughly 75 characters at our body size, which is where prose stops
  /// being comfortable to track line to line.
  static const double narrow = 720;

  /// The default page: card stacks, lists, forms.
  static const double standard = 1080;

  /// Dashboards that genuinely earn a second and third column.
  static const double wide = 1360;
}
