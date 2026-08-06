import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/widgets.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';
import 'google_web_button.dart';

/// Sign Up screen backed by Supabase Auth.
///
/// Collects: full name, email, password, confirm password.
/// Validates all fields before calling [AuthController.signUp].
/// Handles the "email confirmation required" case gracefully.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;
  bool _emailConfirmationPending = false;
  UserRole _role = UserRole.patient;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _emailConfirmationPending = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final error = await ref.read(authControllerProvider.notifier).signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          role: _role,
        );

    if (!mounted) return;

    if (error != null) {
      // The "confirm your email" message is still a positive outcome — show it
      // as an informational notice rather than a red error.
      if (error.toLowerCase().contains('confirm your email') ||
          error.toLowerCase().contains('check your email')) {
        setState(() => _emailConfirmationPending = true);
      } else {
        setState(() => _errorMessage = error);
      }
    }
    // On actual success (no email confirm needed), the auth stream will push
    // the router to /auth/onboarding or /home automatically.
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _errorMessage = null;
      _emailConfirmationPending = false;
    });
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  /// Called once the user completes sign-in through Google's own rendered
  /// button (web only — see [GoogleWebButton]).
  Future<void> _googleWebSignedIn(GoogleWebCredential credential) async {
    setState(() {
      _errorMessage = null;
      _emailConfirmationPending = false;
    });
    await ref
        .read(authControllerProvider.notifier)
        .completeGoogleWebAuth(credential);
    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isLoading = auth.isLoading;

    return GradientScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go(Routes.signIn),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),

                // Header
                Text(
                  'Create your account',
                  style: AppTypography.headlineMd
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Join MedIntel Nexus to manage your health intelligently.',
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),

                _RoleToggle(
                  value: _role,
                  enabled: !isLoading,
                  onChanged: (role) => setState(() => _role = role),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Email confirmation notice
                if (_emailConfirmationPending) ...[
                  const _InfoBanner(
                    icon: Icons.mark_email_read_rounded,
                    color: AppColors.success,
                    message:
                        'Account created! Please check your inbox and confirm your email address before signing in.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Error banner
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Full name
                AppTextField(
                  controller: _name,
                  label: 'Full name',
                  hint: 'Dr. Jane Smith',
                  prefixIcon: Icons.person_outline_rounded,
                  keyboardType: TextInputType.name,
                  validator: Validators.fullName,
                  enabled: !isLoading,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Email
                AppTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@example.com',
                  prefixIcon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  enabled: !isLoading,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Password
                AppTextField(
                  controller: _password,
                  label: 'Password',
                  hint: '••••••••',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  validator: Validators.password,
                  enabled: !isLoading,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    'Min 8 characters · 1 uppercase · 1 number',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Confirm password
                AppTextField(
                  controller: _confirm,
                  label: 'Confirm password',
                  hint: '••••••••',
                  prefixIcon: Icons.lock_rounded,
                  obscureText: _obscureConfirm,
                  validator: Validators.confirmPassword(_password.text),
                  enabled: !isLoading,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Create account button
                PrimaryButton(
                  label: 'Create account',
                  icon: Icons.person_add_rounded,
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _submit,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Divider
                const _OrDivider(),
                const SizedBox(height: AppSpacing.lg),

                // Google Sign-In — web can't use the tap-to-signIn() flow
                // reliably (see GoogleWebButton's doc), so it renders
                // Google's own button instead, which handles its own clicks.
                if (kIsWeb)
                  GoogleWebButton(
                    size: 52,
                    style: GoogleWebButtonStyle.fullWidthStandard,
                    onSignedIn: _googleWebSignedIn,
                  )
                else
                  _GoogleSignInButton(
                    onPressed: isLoading ? null : _googleSignIn,
                    isLoading: isLoading,
                  ),
                const SizedBox(height: AppSpacing.xxl),

                // Sign in link
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Already have an account?',
                        style: AppTypography.bodyMd
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      TextButton(
                        onPressed:
                            isLoading ? null : () => context.go(Routes.signIn),
                        child: Text(
                          'Sign in',
                          style: AppTypography.labelMd
                              .copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Patient vs caregiver account-type picker. Purely a sign-up-time choice —
/// caregiver accounts skip health-profile onboarding entirely and land on a
/// dedicated dashboard (see `AuthController._withResolvedRole` and
/// `Routes.caregiverHome`) instead of the patient's own health tools.
class _RoleToggle extends StatelessWidget {
  const _RoleToggle({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final UserRole value;
  final ValueChanged<UserRole> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.tintBlue.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RoleOption(
              label: "I'm a patient",
              icon: Icons.person_rounded,
              selected: value == UserRole.patient,
              onTap:
                  enabled ? () => onChanged(UserRole.patient) : null,
            ),
          ),
          Expanded(
            child: _RoleOption(
              label: "I'm a caregiver",
              icon: Icons.favorite_rounded,
              selected: value == UserRole.caregiver,
              onTap:
                  enabled ? () => onChanged(UserRole.caregiver) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelMd.copyWith(
                color:
                    selected ? AppColors.primaryDeep : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            'or continue with',
            style:
                AppTypography.caption.copyWith(color: AppColors.textTertiary),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({this.onPressed, this.isLoading = false});
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.outline, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoogleLogo(size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Continue with Google',
                    style: AppTypography.labelLg
                        .copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMd.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMd.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
