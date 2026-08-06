import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_names.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/google_logo.dart';
import '../application/auth_controller.dart';
import 'google_web_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local design tokens.
//
// This screen intentionally does NOT use AppColors: the sign-in experience has
// its own mint/emerald identity (frosted-glass card over a pale clinical
// backdrop), while the authenticated app stays on the blue AppColors brand.
// Keeping them here means restyling this screen can never regress the rest of
// the app's theme.
// ─────────────────────────────────────────────────────────────────────────────

const Color _bg = Color(0xFFF1F4F6);
const Color _green = Color(0xFF12A97D);
const Color _greenLight = Color(0xFF5FD6A4);
const Color _greenDeep = Color(0xFF0B8F63);
const Color _ink = Color(0xFF1B2B33);
const Color _muted = Color(0xFF7C8D96);
const Color _fieldFill = Color(0xFFFBFCFC);
const Color _fieldStroke = Color(0xFFE8EDF0);
const Color _backdropTint = Color(0xFFB9D2E4);

const LinearGradient _brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_greenLight, _greenDeep],
);

/// Full Sign In screen backed by Supabase Auth.
///
/// Supports:
///  - Email + password sign in (with show/hide toggle)
///  - Google Sign-In (native Google picker → Supabase idToken flow)
///  - Forgot password navigation
///  - Sign up navigation
///  - Inline error banner for auth failures
class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _rememberMe = true;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authControllerProvider.notifier).loginWithEmail(
          _email.text.trim(),
          _password.text,
        );
    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _errorMessage = null);
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
    setState(() => _errorMessage = null);
    await ref
        .read(authControllerProvider.notifier)
        .completeGoogleWebAuth(credential);
    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  /// Apple Sign-In has no provider wired up yet (no Apple Developer team /
  /// Supabase Apple provider configured), so this fails loudly-but-politely
  /// instead of silently doing nothing.
  void _appleSignIn() {
    setState(
      () => _errorMessage =
          'Apple Sign-In isn’t set up yet. Use email or Google for now.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isLoading = auth.isLoading;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _MedicalBackdrop()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  const _BrandLogo(),
                  const SizedBox(height: 18),
                  const _BrandWordmark(),
                  const SizedBox(height: 8),
                  const Text(
                    'Smart Care. Better Life.',
                    style: TextStyle(
                      fontSize: 15,
                      color: _muted,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 34),

                  _GlassCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to continue to your account',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: _muted),
                          ),
                          const SizedBox(height: 26),

                          if (_errorMessage != null) ...[
                            _ErrorBanner(message: _errorMessage!),
                            const SizedBox(height: 18),
                          ],

                          _PillField(
                            controller: _email,
                            hint: 'Email Address',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            validator: Validators.email,
                            enabled: !isLoading,
                          ),
                          const SizedBox(height: 16),

                          _PillField(
                            controller: _password,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            validator: Validators.password,
                            enabled: !isLoading,
                            trailing: IconButton(
                              splashRadius: 20,
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 21,
                                color: _muted,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),

                          const SizedBox(height: 14),
                          _RememberRow(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v),
                            onForgot: isLoading
                                ? null
                                : () => context.go(Routes.forgotPassword),
                          ),

                          const SizedBox(height: 22),
                          _GradientButton(
                            label: 'Log In',
                            isLoading: isLoading,
                            onPressed: isLoading ? null : _submit,
                          ),

                          const SizedBox(height: 24),
                          const _OrDivider(),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _SocialButton(
                                // Web can't use the tap-to-signIn() flow
                                // reliably (see GoogleWebButton's doc) — it
                                // renders Google's own button as the child
                                // instead, which handles its own clicks.
                                onTap:
                                    kIsWeb ? null : (isLoading ? null : _googleSignIn),
                                child: kIsWeb
                                    ? GoogleWebButton(
                                        size: 44,
                                        onSignedIn: _googleWebSignedIn,
                                      )
                                    : const GoogleLogo(size: 26),
                              ),
                              const SizedBox(width: 18),
                              _SocialButton(
                                onTap: isLoading ? null : _appleSignIn,
                                child: const Icon(
                                  Icons.apple,
                                  size: 30,
                                  color: Color(0xFF111111),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account?",
                        style: TextStyle(fontSize: 14, color: _muted),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap:
                            isLoading ? null : () => context.go(Routes.signUp),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ),
                    ],
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
// Backdrop — pale, frosted medical iconography scattered behind the content.
// Purely decorative, so it's wrapped in IgnorePointer + ExcludeSemantics.
// ─────────────────────────────────────────────────────────────────────────────

class _MedicalBackdrop extends StatelessWidget {
  const _MedicalBackdrop();

  static const List<(Alignment, IconData, double, double, double)> _items = [
    // (alignment, icon, size, opacity, rotation-turns)
    (Alignment(-0.78, -0.92), Icons.medical_services_outlined, 86, .30, -.05),
    (Alignment(0.02, -0.86), Icons.favorite_rounded, 96, .22, .04),
    (Alignment(0.55, -0.90), Icons.medication_rounded, 74, .26, .10),
    (Alignment(0.92, -0.88), Icons.biotech_rounded, 78, .24, -.03),
    (Alignment(-0.95, -0.66), Icons.add_rounded, 72, .26, 0),
    (Alignment(-0.42, -0.70), Icons.monitor_heart_outlined, 92, .24, 0),
    (Alignment(0.80, -0.60), Icons.content_paste_rounded, 80, .24, .03),
    (Alignment(0.95, -0.38), Icons.apartment_rounded, 88, .26, 0),
    (Alignment(-0.92, -0.10), Icons.vaccines_rounded, 92, .26, -.08),
    (Alignment(0.96, 0.02), Icons.water_drop_rounded, 62, .20, 0),
    (Alignment(-0.90, 0.62), Icons.medication_liquid_rounded, 82, .26, -.04),
    (Alignment(0.88, 0.70), Icons.science_outlined, 84, .26, .05),
    (Alignment(-0.30, 0.95), Icons.medication_rounded, 66, .22, .12),
    (Alignment(0.30, 0.92), Icons.bloodtype_outlined, 58, .18, 0),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          children: [
            for (final (align, icon, size, opacity, turns) in _items)
              Align(
                alignment: align,
                child: Transform.rotate(
                  angle: turns * 6.2831853,
                  child: Icon(
                    icon,
                    size: size,
                    color: _backdropTint.withValues(alpha: opacity),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand
// ─────────────────────────────────────────────────────────────────────────────

/// Medical cross built from two rounded bars under a gradient shader, with a
/// white leaf tucked into the lower-right quadrant — drawn rather than shipped
/// as an asset so it stays crisp at any density.
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 116,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => _brandGradient.createShader(r),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _bar(width: 40, height: 112),
                _bar(width: 112, height: 40),
              ],
            ),
          ),
          Positioned(
            right: 14,
            bottom: 16,
            child: Transform.rotate(
              angle: -0.35,
              child: const Icon(
                Icons.eco_rounded,
                size: 52,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar({required double width, required double height}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
      );
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'MedIntel ',
            style: TextStyle(color: _ink),
          ),
          TextSpan(
            text: 'Nexus',
            style: TextStyle(color: _green),
          ),
        ],
      ),
      style: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.1,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted card
// ─────────────────────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.85),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA4B4).withValues(alpha: 0.16),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form primitives
// ─────────────────────────────────────────────────────────────────────────────

class _PillField extends StatelessWidget {
  const _PillField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.trailing,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Widget? trailing;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      enabled: enabled,
      style: const TextStyle(fontSize: 16, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 16, color: _muted),
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 19),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 20, right: 14),
          child: Icon(icon, size: 23, color: _green),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: trailing,
        border: _border(_fieldStroke),
        enabledBorder: _border(_fieldStroke),
        focusedBorder: _border(_green.withValues(alpha: 0.55), width: 1.6),
        errorBorder: _border(const Color(0xFFE57373)),
        focusedErrorBorder: _border(const Color(0xFFE57373), width: 1.6),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.2}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: color, width: width),
      );
}

class _RememberRow extends StatelessWidget {
  const _RememberRow({
    required this.value,
    required this.onChanged,
    required this.onForgot,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onForgot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => onChanged(!value),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  color: value ? _green : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value ? _green : const Color(0xFFC3D0D7),
                    width: 1.6,
                  ),
                ),
                child: value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 15,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              const Text(
                'Remember me',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onForgot,
          child: const Text(
            'Forgot Password?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _green,
            ),
          ),
        ),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.65,
        child: Container(
          height: 62,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: _brandGradient,
            borderRadius: BorderRadius.circular(31),
            boxShadow: [
              BoxShadow(
                color: _green.withValues(alpha: 0.42),
                blurRadius: 26,
                spreadRadius: -2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 21,
                        color: Colors.white,
                      ),
                    ],
                  ),
          ),
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
        Expanded(child: Container(height: 1, color: const Color(0xFFDFE7EB))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or continue with',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Expanded(child: Container(height: 1, color: const Color(0xFFDFE7EB))),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 78,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8DA4B4).withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFD64545);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13.5, color: danger),
            ),
          ),
        ],
      ),
    );
  }
}
