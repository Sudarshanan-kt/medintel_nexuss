import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/google_logo.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Caregiver identity.
//
// Violet, deliberately — the same distinction the dashboard already draws
// between patient and caregiver mode. Someone looking after a parent should
// be able to tell at a glance which side of the app they're in, and the
// colour is the fastest way to say it.
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFFF4F1FC);
const Color _violet = Color(0xFF7C5CFC);
const Color _violetLight = Color(0xFFB6A4FF);
const Color _violetDeep = Color(0xFF5B3FD9);
const Color _violetSoft = Color(0xFFEEE9FE);
const Color _ink = Color(0xFF241E3B);
const Color _muted = Color(0xFF7C748F);
const Color _fieldFill = Color(0xFFFCFBFF);
const Color _fieldStroke = Color(0xFFE7E1F7);

const LinearGradient _caregiverGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_violetLight, _violetDeep],
);

/// Sign-in for people who look after someone else.
///
/// The form is the same Supabase email/Google flow the patient screen uses —
/// what differs is the identity and the expectations it sets. A caregiver
/// arriving here should understand immediately that they'll see someone
/// else's medicines, not their own.
///
/// Choosing this screen does **not** grant caregiver access. It's passed as
/// a hint for accounts that have no role yet (a first Google sign-in); an
/// existing account always keeps the role on its profile. Picking the wrong
/// door can't get you someone else's data.
class CaregiverLoginScreen extends ConsumerStatefulWidget {
  const CaregiverLoginScreen({super.key});

  @override
  ConsumerState<CaregiverLoginScreen> createState() =>
      _CaregiverLoginScreenState();
}

class _CaregiverLoginScreenState extends ConsumerState<CaregiverLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _captureError() {
    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authControllerProvider.notifier).loginWithEmail(
          _email.text.trim(),
          _password.text,
          roleHint: UserRole.caregiver,
        );
    _captureError();
  }

  Future<void> _googleSignIn() async {
    setState(() => _errorMessage = null);
    await ref
        .read(authControllerProvider.notifier)
        .signInWithGoogle(roleHint: UserRole.caregiver);
    _captureError();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _CaregiverBackdrop()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: _ink),
                      onPressed: () => context.go(Routes.signIn),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _CaregiverMark(),
                  const SizedBox(height: 22),
                  const Text(
                    'Caregiver sign in',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Keep track of the medicines and appointments\n'
                    'of someone you look after.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: _muted, height: 1.45),
                  ),
                  const SizedBox(height: 26),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _fieldStroke),
                      boxShadow: [
                        BoxShadow(
                          color: _violetDeep.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorMessage != null) ...[
                            _ErrorBanner(message: _errorMessage!),
                            const SizedBox(height: 14),
                          ],
                          _Field(
                            controller: _email,
                            hint: 'Email address',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _password,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscure: _obscure,
                            validator: Validators.password,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: _muted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.go(Routes.forgotPassword),
                              child: const Text(
                                'Forgot password?',
                                style: TextStyle(
                                  color: _violet,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _PrimaryButton(
                            label: 'Sign in as caregiver',
                            isLoading: isLoading,
                            onPressed: isLoading ? null : _submit,
                          ),
                          const SizedBox(height: 16),
                          const _OrDivider(),
                          const SizedBox(height: 16),
                          _GoogleButton(
                            onPressed: isLoading ? null : _googleSignIn,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),
                  // The way back for someone who took the wrong door.
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Managing your own medicines?',
                          style: TextStyle(color: _muted, fontSize: 13.5),
                        ),
                        TextButton(
                          onPressed: () => context.go(Routes.signIn),
                          child: const Text(
                            'Patient sign in',
                            style: TextStyle(
                              color: _violetDeep,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go(Routes.signUp),
                      child: const Text(
                        'Create a caregiver account',
                        style: TextStyle(
                          color: _violet,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pieces
// ─────────────────────────────────────────────────────────────────────────────

/// Two overlapping figures — the caregiver and the person cared for. Says
/// what this side of the app is for before a word is read.
class _CaregiverMark extends StatelessWidget {
  const _CaregiverMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 78,
        height: 78,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: _caregiverGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _violetDeep.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.volunteer_activism_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

/// Faint care-themed motifs, matching the patient screen's treatment but in
/// the caregiver palette.
class _CaregiverBackdrop extends StatelessWidget {
  const _CaregiverBackdrop();

  static const List<(Alignment, IconData, double, double)> _items = [
    (Alignment(-0.85, -0.92), Icons.favorite_rounded, 54, .16),
    (Alignment(0.80, -0.88), Icons.groups_rounded, 62, .14),
    (Alignment(0.92, -0.45), Icons.medication_rounded, 46, .13),
    (Alignment(-0.92, -0.30), Icons.notifications_active_rounded, 48, .12),
    (Alignment(-0.70, 0.85), Icons.health_and_safety_rounded, 58, .12),
    (Alignment(0.85, 0.80), Icons.calendar_month_rounded, 50, .12),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            for (final (align, icon, size, opacity) in _items)
              Align(
                alignment: align,
                child: Icon(
                  icon,
                  size: size,
                  color: _violet.withValues(alpha: opacity),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: _ink, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 14.5),
        prefixIcon: Icon(icon, color: _muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _violet, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: onPressed == null ? null : _caregiverGradient,
          color: onPressed == null ? _violetSoft : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: _violetDeep.withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const GoogleLogo(size: 18),
      label: const Text(
        'Continue with Google',
        style: TextStyle(
          color: _ink,
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: _fieldStroke),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: _fieldStroke)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: _muted, fontSize: 13)),
        ),
        Expanded(child: Divider(color: _fieldStroke)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tintRed,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.dangerDeep, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.dangerDeep,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
