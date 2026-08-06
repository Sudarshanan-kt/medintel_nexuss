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
