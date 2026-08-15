import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/navigation.dart';
import '../../../app/router/route_names.dart';
import '../../../core/constants/demo_otp.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_controller.dart';
import '../data/demo_otp_repository.dart';
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
/// Caregivers have no password. They enter a mobile number, receive a
/// six-digit code by SMS, and type it in — that is the whole flow. A
/// caregiver account is typically created once, when an older relative
/// redeems an invite, and then used occasionally; a password set on that day
/// and needed again three months later is the step most likely to lose them.
/// A phone is also the one credential that audience reliably has — an email
/// address often isn't.
///
/// Choosing this screen does **not** grant caregiver access. The role is
/// passed only as a hint for accounts that have none yet (a brand-new
/// caregiver's first sign-in); an existing account always keeps the role
/// recorded on its profile. Coming through the wrong door cannot get you
/// somebody else's data.
class CaregiverLoginScreen extends ConsumerStatefulWidget {
  const CaregiverLoginScreen({super.key});

  @override
  ConsumerState<CaregiverLoginScreen> createState() =>
      _CaregiverLoginScreenState();
}

class _CaregiverLoginScreenState extends ConsumerState<CaregiverLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _phoneFormKey = GlobalKey<FormState>();

  /// Dialling code prefixed to whatever is typed.
  ///
  /// Supabase requires E.164 (`+919876543210`) and rejects anything else, so
  /// the country code can't be optional. Offering it as a picker with a
  /// sensible default beats asking people to remember to type "+91".
  String _dialCode = '+91';

  /// Which half of the flow is on screen. There is no password step at all.
  bool _codeSent = false;
  bool _sending = false;
  String? _errorMessage;

  /// Seconds until "Resend code" becomes available again.
  ///
  /// Supabase rate-limits repeat sends per address and returns an error that
  /// reads like a fault. Counting down here means the button is simply
  /// unavailable until it would work, instead of failing when pressed.
  int _resendIn = 0;
  Timer? _resendTimer;

  /// The code Auth just generated, when it's being shown rather than texted.
  /// Null until a send succeeds, and again on every new send.
  String? _demoCode;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  /// The number in the form Supabase accepts: dialling code, then digits
  /// only. Strips spaces, dashes and brackets people naturally type, and a
  /// leading 0 — Indian numbers are often written "09876543210" but E.164
  /// has no trunk prefix.
  String get _e164 {
    var digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '$_dialCode$digits';
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!resend && !(_phoneFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _errorMessage = null;
      _sending = true;
    });

    final error =
        await ref.read(authControllerProvider.notifier).sendPhoneOtp(_e164);

    if (!mounted) return;
    setState(() {
      _sending = false;
      _errorMessage = error;
      if (error == null) _codeSent = true;
    });
    if (error == null) {
      _startResendCooldown();
      if (DemoOtpConfig.isEnabled) await _loadDemoCode();
    }
  }

  /// Fetches the code Auth generated for this send, for display.
  ///
  /// The hook writes it inside the send request, so it is there by the time
  /// that request returns. The one retry covers replication lag rather than a
  /// race — and a miss only costs the on-screen copy, never the sign-in.
  Future<void> _loadDemoCode() async {
    setState(() => _demoCode = null);
    final repo = ref.read(demoOtpRepositoryProvider);
    var code = await repo.latestCodeFor(_e164);
    if (code == null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      code = await repo.latestCodeFor(_e164);
    }
    if (!mounted) return;
    setState(() => _demoCode = code);
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code.');
      return;
    }
    setState(() => _errorMessage = null);

    await ref.read(authControllerProvider.notifier).verifyPhoneOtp(
          _e164,
          _code.text,
          roleHint: UserRole.caregiver,
        );

    if (!mounted) return;
    final authState = ref.read(authControllerProvider).valueOrNull;
    if (authState?.errorMessage != null) {
      setState(() => _errorMessage = authState!.errorMessage);
    }
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _codeSent = false;
      _resendIn = 0;
      _code.clear();
      _errorMessage = null;
      _demoCode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading || _sending;

    return Scaffold(
      backgroundColor: _bg,
      // SizedBox.expand matters, the same way it does on the patient screen:
      // the Stack's only unpositioned child is the scroll view, which gets
      // loose constraints and shrink-wraps its content. The Stack then takes
      // that height, and Positioned.fill fills the content — not the screen —
      // so the lower motifs land under the card instead of in the bottom
      // corners and everything below is bare.
      body: SizedBox.expand(
        child: Stack(
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
                        onPressed: () => _codeSent
                            ? _changeNumber()
                            : context.backOr(Routes.signIn),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const _CaregiverMark(),
                    const SizedBox(height: 22),
                    Text(
                      _codeSent ? 'Enter your code' : 'Caregiver sign in',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      !_codeSent
                          ? 'Keep track of the medicines and appointments\n'
                              'of someone you look after.'
                          : DemoOtpConfig.isEnabled
                              // Nothing was texted, so don't say it was.
                              ? 'Signing in as\n$_e164'
                              : 'We texted a 6-digit code to\n$_e164',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _muted,
                        height: 1.45,
                      ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorMessage != null) ...[
                            _ErrorBanner(message: _errorMessage!),
                            const SizedBox(height: 14),
                          ],
                          if (!_codeSent)
                            ..._phoneStep(isLoading)
                          else
                            ..._codeStep(isLoading),
                        ],
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
                            onPressed: () => context.backOr(Routes.signIn),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _phoneStep(bool isLoading) => [
        Form(
          key: _phoneFormKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialCodePicker(
                value: _dialCode,
                onChanged: isLoading
                    ? null
                    : (code) => setState(() => _dialCode = code),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Field(
                  controller: _phone,
                  hint: 'Mobile number',
                  icon: Icons.phone_iphone_rounded,
                  keyboardType: TextInputType.phone,
                  validator: Validators.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onSubmitted: (_) => isLoading ? null : _sendCode(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: DemoOtpConfig.isEnabled ? 'Show my code' : 'Text me a code',
          isLoading: isLoading,
          onPressed: isLoading ? null : _sendCode,
        ),
        const SizedBox(height: 14),
        Text(
          DemoOtpConfig.isEnabled
              ? 'No password needed — the code appears on the next screen.'
              : "No password needed — we'll text a code each time you sign in.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: _muted, height: 1.4),
        ),
      ];

  List<Widget> _codeStep(bool isLoading) => [
        if (DemoOtpConfig.isEnabled) ...[
          _DemoCodeBanner(code: _demoCode),
          const SizedBox(height: 14),
        ],
        _Field(
          controller: _code,
          hint: '6-digit code',
          icon: Icons.sms_outlined,
          keyboardType: TextInputType.number,
          // Lets Android and iOS drop the code straight in from the SMS.
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          autofocus: true,
          onSubmitted: (_) => isLoading ? null : _verify(),
        ),
        const SizedBox(height: 4),
        _PrimaryButton(
          label: 'Sign in as caregiver',
          isLoading: isLoading,
          onPressed: isLoading ? null : _verify,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: isLoading ? null : _changeNumber,
              child: const Text(
                'Change number',
                style: TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: (isLoading || _resendIn > 0)
                  ? null
                  : () => _sendCode(resend: true),
              child: Text(
                _resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code',
                style: TextStyle(
                  color: _resendIn > 0 ? _muted : _violet,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ];
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

/// Country dialling code.
///
/// Deliberately a short list rather than every country on earth: this app's
/// users are in India, with a handful of relatives abroad who might be in a
/// care circle. A 200-entry scroll would be worse for everyone.
class _DialCodePicker extends StatelessWidget {
  const _DialCodePicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String>? onChanged;

  static const _codes = <String, String>{
    '+91': 'IN',
    '+1': 'US',
    '+44': 'UK',
    '+61': 'AU',
    '+65': 'SG',
    '+971': 'AE',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _fieldStroke),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          onChanged: onChanged == null
              ? null
              : (v) => v == null ? null : onChanged!(v),
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          style: const TextStyle(color: _ink, fontSize: 15),
          icon: const Icon(Icons.expand_more_rounded, color: _muted, size: 18),
          items: [
            for (final entry in _codes.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  '${entry.value} ${entry.key}',
                  style: const TextStyle(color: _ink, fontSize: 15),
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
    this.keyboardType,
    this.validator,
    this.autofillHints,
    this.maxLength,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  /// Lets the platform offer the emailed code straight from the notification
  /// (`AutofillHints.oneTimeCode`) — the difference between typing six
  /// digits and tapping once.
  final Iterable<String>? autofillHints;

  final int? maxLength;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      autofillHints: autofillHints,
      maxLength: maxLength,
      autofocus: autofocus,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: _ink, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: _muted, fontSize: 14.5),
        prefixIcon: Icon(icon, color: _muted, size: 20),
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

/// The sign-in code, on screen, because no SMS was sent.
///
/// Labelled rather than quietly shown: someone watching a demo should be
/// able to see that this stands in for a text message, not that the app
/// leaks codes. See [DemoOtpConfig] for what makes it appear.
class _DemoCodeBanner extends StatelessWidget {
  const _DemoCodeBanner({required this.code});

  /// Null while the code is still being read back, or if it couldn't be —
  /// which is worth saying out loud rather than showing an empty space, since
  /// there is no text message coming to fall back on.
  final String? code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _violetSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _violet.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.phonelink_lock_rounded,
            color: _violetDeep,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Demo sign-in — no text message sent',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                if (code != null)
                  Text(
                    code!,
                    style: const TextStyle(
                      color: _violetDeep,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      // Wide enough to read off a projector, and to copy by
                      // eye without losing the place.
                      letterSpacing: 6,
                    ),
                  )
                else
                  const Text(
                    'Reading the code…',
                    style: TextStyle(
                      color: _violetDeep,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
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
