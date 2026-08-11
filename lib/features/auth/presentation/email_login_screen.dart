import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/floating_medical_field.dart';
import '../../../shared/widgets/google_logo.dart';
import '../application/auth_controller.dart';
import 'google_web_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local design tokens.
//
// This screen deliberately keeps its own palette rather than reading the full
// AppColors set: sign-in has a pale mint identity (mint motifs floating over
// an almost-white wash, one white card) that the authenticated app doesn't
// share. Only the brand green is pulled from AppColors, so a brand change
// still lands here.
// ─────────────────────────────────────────────────────────────────────────────

const Color _green = AppColors.primary;
const Color _greenDeep = AppColors.primaryDeep;
const Color _ink = Color(0xFF16232E);
const Color _muted = Color(0xFF8496A0);
const Color _fieldStroke = Color(0xFFE9EFF1);

/// The card and its fields are deliberately translucent: the motifs drifting
/// underneath stay visible through them, which is the whole point of the
/// floating field. Pushed much past this and the form text starts competing
/// with whatever passes behind it.
const Color _cardFill = Color(0xB5FFFFFF); // white @ 71%
const Color _fieldFill = Color(0x8CFFFFFF); // white @ 55%

/// The wash behind everything: near-white, with the faintest mint lift at the
/// top and bottom so the card has something to sit on.
const LinearGradient _pageWash = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFEDF6F2), Color(0xFFF7FBFA), Color(0xFFEAF4F0)],
  stops: [0, 0.45, 1],
);

/// Violet, matching the caregiver side of the app — the link to it should
/// look like where it leads, not like the rest of this screen.
const Color _caregiverAccent = Color(0xFF7C5CFC);

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
      // SizedBox.expand matters: the Stack below sizes itself to the scroll
      // content, which is shorter than the screen on a tall phone. Without
      // it the wash (and the motif field) stop above the bottom edge and the
      // Scaffold's own grey shows through underneath.
      body: SizedBox.expand(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: _pageWash),
          child: Stack(
            children: [
              const Positioned.fill(
                child: FloatingMedicalField(
                  specs: FloatingMedicalField.defaultSignInField,
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
                    child: ConstrainedBox(
                      // Fill the viewport (minus the padding above) so the
                      // column has room to centre itself; the slack then
                      // splits evenly above and below instead of all
                      // collecting at the bottom. When the content is taller
                      // than the screen — keyboard up, or an error banner
                      // showing — this does nothing and it simply scrolls.
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 32,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const _BrandBlock(),
                          const SizedBox(height: 22),
                          // The card is inset well past the page padding so the
                          // motifs on either side stay in open space rather than
                          // disappearing behind it — they're meant to frame it.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: _SignInCard(
                              formKey: _formKey,
                              email: _email,
                              password: _password,
                              obscure: _obscure,
                              isLoading: isLoading,
                              errorMessage: _errorMessage,
                              onToggleObscure: () =>
                                  setState(() => _obscure = !_obscure),
                              onSubmit: isLoading ? null : _submit,
                              onForgot: isLoading
                                  ? null
                                  : () => context.openScreen(Routes.forgotPassword),
                              onSignUp: isLoading
                                  ? null
                                  : () => context.openScreen(Routes.signUp),
                              onGoogle: isLoading ? null : _googleSignIn,
                              onGoogleWeb: _googleWebSignedIn,
                              onApple: isLoading ? null : _appleSignIn,
                            ),
                          ),

                          // The other door. Someone looking after a parent has no
                          // reason to guess that this screen would work for them,
                          // so the caregiver side is named explicitly.
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: isLoading
                                ? null
                                : () => context.openScreen(Routes.caregiverSignIn),
                            icon: const Icon(
                              Icons.volunteer_activism_rounded,
                              size: 17,
                              color: _caregiverAccent,
                            ),
                            label: const Text(
                              "I'm caring for someone else",
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: _caregiverAccent,
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),
                          const _TrustFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Brand block — icon, wordmark, tagline.
// ─────────────────────────────────────────────────────────────────────────────

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // The real launcher icon, so the screen matches the tile the user
        // tapped to get here.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _greenDeep.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/branding/app_icon.png',
              width: 76,
              height: 76,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'MedIntel',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.8,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SparkleMark(size: 13, color: _green),
            SizedBox(width: 8),
            Text(
              'NEXUS',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: _green,
                letterSpacing: 5.5,
                height: 1.1,
              ),
            ),
            SizedBox(width: 3),
            SparkleMark(size: 13, color: _green),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Smarter Healthcare, Better Life.',
          style: TextStyle(fontSize: 14, color: _muted, height: 1.3),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The card
// ─────────────────────────────────────────────────────────────────────────────

class _SignInCard extends StatelessWidget {
  const _SignInCard({
    required this.formKey,
    required this.email,
    required this.password,
    required this.obscure,
    required this.isLoading,
    required this.errorMessage,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgot,
    required this.onSignUp,
    required this.onGoogle,
    required this.onGoogleWeb,
    required this.onApple,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool obscure;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onToggleObscure;
  final VoidCallback? onSubmit;
  final VoidCallback? onForgot;
  final VoidCallback? onSignUp;
  final VoidCallback? onGoogle;
  final ValueChanged<GoogleWebCredential> onGoogleWeb;
  final VoidCallback? onApple;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E5E52).withValues(alpha: 0.09),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome Back!',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Sign in to continue',
              style: TextStyle(fontSize: 14.5, color: _muted),
            ),
            const SizedBox(height: 22),
            if (errorMessage != null) ...[
              _ErrorBanner(message: errorMessage!),
              const SizedBox(height: 16),
            ],
            _Field(
              controller: email,
              hint: 'Email Address',
              icon: Icons.person_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              enabled: !isLoading,
            ),
            const SizedBox(height: 14),
            _Field(
              controller: password,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: obscure,
              validator: Validators.password,
              enabled: !isLoading,
              trailing: IconButton(
                splashRadius: 20,
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: _muted,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onForgot,
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _LoginButton(isLoading: isLoading, onPressed: onSubmit),
            const SizedBox(height: 20),
            const _OrDivider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _SocialButton(
                    // Web can't use the tap-to-signIn() flow reliably (see
                    // GoogleWebButton's doc) — it renders Google's own button
                    // as the child instead, which handles its own clicks.
                    onTap: kIsWeb ? null : onGoogle,
                    icon: kIsWeb
                        ? GoogleWebButton(size: 22, onSignedIn: onGoogleWeb)
                        : const GoogleLogo(size: 20),
                    label: 'Google',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SocialButton(
                    onTap: onApple,
                    icon: const Icon(
                      Icons.apple,
                      size: 24,
                      color: Color(0xFF111111),
                    ),
                    label: 'Apple',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'New to MedIntel Nexus?',
                  style: TextStyle(fontSize: 13.5, color: _muted),
                ),
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: onSignUp,
                  child: const Text(
                    'Sign Up',
                    style: TextStyle(
                      fontSize: 13.5,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card internals
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.trailing,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      enabled: enabled,
      style: const TextStyle(fontSize: 15, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15, color: _muted),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, size: 21, color: _green),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: trailing,
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        border: _border(_fieldStroke),
        enabledBorder: _border(_fieldStroke),
        focusedBorder: _border(_green, width: 1.4),
        errorBorder: _border(const Color(0xFFEF4444)),
        focusedErrorBorder: _border(const Color(0xFFEF4444), width: 1.4),
      ),
    );
  }

  OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: width),
      );
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_green, _greenDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: _greenDeep.withValues(alpha: 0.32),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: onPressed,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ],
                    ),
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
    return const Row(
      children: [
        Expanded(child: Divider(color: _fieldStroke, thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or continue with',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        Expanded(child: Divider(color: _fieldStroke, thickness: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onTap;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fieldFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _fieldStroke),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF6C9C9)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_user_rounded, size: 14, color: _green),
            const SizedBox(width: 6),
            Text(
              'Your data is safe and secure',
              style: TextStyle(
                fontSize: 12.5,
                color: _muted.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'We follow HIPAA compliant standards',
          style: TextStyle(
            fontSize: 12.5,
            color: _muted.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
