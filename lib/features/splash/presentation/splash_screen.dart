import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/widgets.dart';
import '../../auth/application/auth_controller.dart';

/// Splash — premium logo reveal + healthcare-AI branding while the auth
/// controller decides where to go next.
///
/// Biometric gate: if the user has a restored session AND has biometric
/// unlock enabled, the system biometric prompt is shown here before the router
/// sends them into the app. If they cancel/fail, they are signed out.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logo;
  late final AnimationController _ring;

  /// Whether we've already run the biometric gate this launch.
  bool _biometricGateDone = false;

  @override
  void initState() {
    super.initState();
    _logo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // Wait for auth to resolve, then run biometric gate (if needed).
    Future<void>.delayed(AppConstants.splashHold, _resolveAuth);
  }

  Future<void> _resolveAuth() async {
    if (!mounted) return;

    final authState = ref.read(authControllerProvider).valueOrNull;
    final hasSession = authState?.status == AuthStatus.authenticated ||
        authState?.status == AuthStatus.onboarding;

    if (hasSession && !_biometricGateDone) {
      _biometricGateDone = true;
      final biometric = ref.read(biometricServiceProvider);
      final passed = await biometric.gateForAppLaunch();

      if (!mounted) return;

      if (!passed) {
        // Failed biometric → sign out to protect the account.
        await ref.read(authControllerProvider.notifier).signOut();
        return;
      }
    }

    // Trigger router redirect by invalidating auth state.
    if (mounted) ref.invalidate(authControllerProvider);
  }

  @override
  void dispose() {
    _logo.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Center(
        child: AnimatedBuilder(
          animation: Listenable.merge([_logo, _ring]),
          builder: (context, _) {
            final logoT = Curves.easeOutBack.transform(_logo.value);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Breathing ring.
                    Opacity(
                      opacity: 0.4 + 0.4 * (1 - _ring.value),
                      child: Container(
                        width: 140 + (24 * _ring.value),
                        height: 140 + (24 * _ring.value),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary
                                .withValues(alpha: 1 - _ring.value),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    // Logo mark.
                    Transform.scale(
                      scale: logoT,
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: AppShadows.brandGlow,
                        ),
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
                Opacity(
                  opacity: _logo.value,
                  child: Column(
                    children: [
                      Text(
                        AppConstants.appName,
                        style: AppTypography.displayLg.copyWith(
                          color: AppColors.textPrimary,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: 280,
                        child: Text(
                          AppConstants.appTagline,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
