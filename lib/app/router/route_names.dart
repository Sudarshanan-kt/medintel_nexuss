/// Typed route paths and names. Screens and redirects reference these
/// constants — never raw strings.
abstract final class Routes {
  // Boot
  static const String splash = '/';

  // Auth
  static const String signIn = '/auth/signin';
  static const String signUp = '/auth/signup';
  static const String forgotPassword = '/auth/forgot-password';
  static const String onboarding = '/auth/onboarding';

  // Shell tabs
  static const String home = '/home';
  static const String caregiverHome = '/caregiver-home';
  static const String assistant = '/assistant';
  static const String scan = '/scan';
  static const String reports = '/reports';
  static const String profile = '/profile';

  // Standalone feature pages
  static const String pharmacies = '/pharmacies';
  static const String reminders = '/reminders';
  static const String sos = '/sos';
  static const String careCircle = '/care-circle';
  static const String healthInsights = '/health-insights';
  static const String healthTimeline = '/health-insights/timeline';
  static const String savings = '/savings';
  static const String interactions = '/interactions';
  static const String biomarkerTrends = '/reports/trends';
  static const String symptomCheck = '/symptom-check';
  static const String inviteAccept = '/invite'; // + /:code
  static String inviteAcceptCode(String code) => '/invite/$code';

  // Nested
  static const String scanReview = '/scan/review';
  static const String scanResult = '/scan/result'; // + /:id
  static String scanResultId(String id) => '/scan/result/$id';
  static String reportById(String id) => '/reports/$id';

  /// Tab order for the bottom navigation / navigation rail.
  static const List<String> shellTabs = [
    home,
    assistant,
    scan,
    reports,
    profile,
  ];
}
