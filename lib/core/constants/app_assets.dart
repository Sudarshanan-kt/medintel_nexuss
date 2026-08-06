/// Typed asset paths. Never reference an asset by raw string.
abstract final class AppAssets {
  static const String _images = 'assets/images';
  static const String _lottie = 'assets/lottie';
  static const String _icons = 'assets/icons';

  // Branding
  static const String logoMark = '$_images/logo_mark.png';
  static const String logoWordmark = '$_images/logo_wordmark.png';

  // Lottie
  static const String splashAnimation = '$_lottie/splash_reveal.json';
  static const String orbAnimation = '$_lottie/ai_orb.json';
  static const String scanningAnimation = '$_lottie/scanning.json';

  // Illustrations / empty states
  static const String emptyReports = '$_images/empty_reports.png';
  static const String onboardingScan = '$_images/onboarding_scan.png';
  static const String onboardingInsights = '$_images/onboarding_insights.png';
  static const String onboardingAssistant =
      '$_images/onboarding_assistant.png';

  // Custom line icons
  static const String icPharmacy = '$_icons/ic_pharmacy.svg';
}
