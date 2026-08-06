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

/// Forgot Password screen.
///
/// Accepts an email address and calls Supabase's password reset endpoint.
/// Shows a success notice so the user knows to check their inbox.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _emailSent = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    final error = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text.trim());
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (error != null) {
        _errorMessage = error;
      } else {
        _emailSent = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: AppSpacing.xxl),

                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Header
                Text(
                  'Forgot your password?',
                  style: AppTypography.headlineMd
                      .copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Enter your email address and we'll send you a link to reset your password.",
                  style: AppTypography.bodyMd
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Success notice
                if (_emailSent) ...[
                  _StatusBanner(
                    icon: Icons.mark_email_read_rounded,
                    color: AppColors.success,
                    message:
                        'Reset link sent! Check your inbox at ${_email.text.trim()} and follow the link to set a new password.',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // Error banner
                if (_errorMessage != null) ...[
                  _StatusBanner(
                    icon: Icons.error_outline_rounded,
                    color: AppColors.danger,
                    message: _errorMessage!,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // Email field (hidden after success)
                if (!_emailSent) ...[
                  AppTextField(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@example.com',
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  PrimaryButton(
                    label: 'Send reset link',
                    icon: Icons.send_rounded,
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
                  ),
                ] else ...[
                  // After sending, show a "send again" option
                  SecondaryButton(
                    label: 'Send again',
                    icon: Icons.refresh_rounded,
                    onPressed: () => setState(() {
                      _emailSent = false;
                      _errorMessage = null;
                    }),
                  ),
                ],

                const SizedBox(height: AppSpacing.xxl),

                // Back to sign in link
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: Text(
                      'Back to sign in',
                      style: AppTypography.labelMd
                          .copyWith(color: AppColors.primary),
                    ),
                    onPressed: () => context.go(Routes.signIn),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
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
      width: double.infinity,
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
