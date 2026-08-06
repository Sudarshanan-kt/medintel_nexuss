import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../features/assistant/presentation/assistant_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/care_circle/presentation/accept_invite_screen.dart';
import '../../features/care_circle/presentation/care_circle_screen.dart';
import '../../features/dashboard/presentation/health_timeline_screen.dart';
import '../../features/interactions/presentation/interaction_checker_screen.dart';
import '../../features/reports/presentation/biomarker_trend_screen.dart';
import '../../features/triage/presentation/triage_result_screen.dart';
import '../../features/vitals/presentation/health_insights_screen.dart';
import '../../features/auth/presentation/email_login_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/healthcare_onboarding_screen.dart';
import '../../features/auth/presentation/sign_up_screen.dart';
import '../../features/dashboard/presentation/app_shell.dart';
import '../../features/dashboard/presentation/home_dashboard_screen.dart';
import '../../features/pharmacies/nearby_pharmacies_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/reminders/medicine_reminder_screen.dart';
import '../../features/reports/presentation/report_viewer_screen.dart';
import '../../features/reports/presentation/reports_list_screen.dart';
import '../../features/savings/presentation/savings_screen.dart';
import '../../features/scan/presentation/scan_result_screen.dart';
import '../../features/scan/presentation/scanner_screen.dart';
import '../../features/sos/presentation/sos_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import 'route_names.dart';

/// The app's [GoRouter], exposed as a provider so it can react to auth state.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = _AuthRefreshListenable(ref);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refreshListenable,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (_, __) => const SplashScreen(),
      ),

      // ── Auth ───────────────────────────────────────────────────────────
      GoRoute(
        path: Routes.signIn,
        pageBuilder: (_, s) => _sharedAxis(s, const EmailLoginScreen()),
      ),
      GoRoute(
        path: Routes.signUp,
        pageBuilder: (_, s) => _sharedAxis(s, const SignUpScreen()),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        pageBuilder: (_, s) => _sharedAxis(s, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const HealthcareOnboardingScreen()),
      ),

      // ── Standalone feature pages ───────────────────────────────────────
      GoRoute(
        path: Routes.pharmacies,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const NearbyPharmaciesScreen()),
      ),
      GoRoute(
        path: Routes.reminders,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const MedicineReminderScreen()),
      ),
      GoRoute(
        path: Routes.sos,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const SosScreen()),
      ),
      GoRoute(
        path: Routes.careCircle,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const CareCircleScreen()),
      ),
      GoRoute(
        path: Routes.healthInsights,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const HealthInsightsScreen()),
      ),
      GoRoute(
        path: Routes.healthTimeline,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const HealthTimelineScreen()),
      ),
      GoRoute(
        path: Routes.savings,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const SavingsScreen()),
      ),
      GoRoute(
        path: Routes.interactions,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const InteractionCheckerScreen()),
      ),
      GoRoute(
        path: Routes.biomarkerTrends,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const BiomarkerTrendScreen()),
      ),
      GoRoute(
        path: Routes.symptomCheck,
        pageBuilder: (_, s) =>
            _sharedAxis(s, const TriageScreen()),
      ),
      GoRoute(
        path: '${Routes.inviteAccept}/:code',
        pageBuilder: (_, s) => _sharedAxis(
          s,
          AcceptInviteScreen(code: s.pathParameters['code'] ?? ''),
        ),
      ),

      // ── Shell (persistent bottom nav with proper tab state) ────────────
      // StatefulShellRoute.indexedStack mounts every branch ONCE and uses
      // IndexedStack to switch between them, so tabs preserve state and
      // never re-render in a broken state when you come back to them.
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (_, __) => const HomeDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.assistant,
                builder: (_, __) => const AssistantScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.scan,
                builder: (_, __) => const ScannerScreen(),
                routes: [
                  GoRoute(
                    path: 'result/:id',
                    pageBuilder: (_, s) => _sharedAxis(
                      s,
                      ScanResultScreen(scanId: s.pathParameters['id'] ?? ''),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.reports,
                builder: (_, __) => const ReportsListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    pageBuilder: (_, s) => _sharedAxis(
                      s,
                      ReportViewerScreen(reportId: s.pathParameters['id'] ?? ''),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Auth guard. Keeps unauthenticated users in `/auth/*`, sends authenticated
/// users out of it, and routes onboarding-incomplete users to onboarding.
String? _redirect(Ref ref, GoRouterState state) {
  final status = ref.read(authStatusProvider);
  final loc = state.matchedLocation;
  final isSplash = loc == Routes.splash;
  final isAuthRoute = loc.startsWith('/auth');

  switch (status) {
    case AuthStatus.unknown:
      return isSplash ? null : Routes.splash;
    case AuthStatus.unauthenticated:
      return isAuthRoute ? null : Routes.signIn;
    case AuthStatus.onboarding:
      return loc == Routes.onboarding ? null : Routes.onboarding;
    case AuthStatus.authenticated:
      return (isAuthRoute || isSplash) ? Routes.home : null;
  }
}

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(authStatusProvider, (_, __) => notifyListeners());
  }
}

CustomTransitionPage<void> _sharedAxis(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.base,
    transitionsBuilder: (_, animation, __, c) {
      final offset = Tween<Offset>(
        begin: const Offset(0.06, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: offset, child: c),
      );
    },
  );
}
