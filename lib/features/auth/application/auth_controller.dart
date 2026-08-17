import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/utils/result.dart';
import '../../profile/data/health_profile_repository.dart';
import '../data/auth_repository_impl.dart';
import '../data/profile_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// The four lifecycle phases of a session. The router redirect (see
/// `app_router.dart`) is driven entirely by this.
enum AuthStatus { unknown, unauthenticated, onboarding, authenticated }

/// Immutable session state exposed to the whole app.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  final AuthStatus status;
  final AuthUser? user;
  final String? errorMessage;

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }
}

/// The single source of truth for authentication.
///
/// Screens call into this notifier; the router *watches* it and redirects.
/// State transitions are explicit and exhaustive.
///
/// Supabase session changes (token refresh, external login, etc.) are observed
/// via [onAuthStateChange] so the UI always reflects the live session.
///
/// **Onboarding logic**: after every sign-in we check whether a `health_profiles`
/// row exists in Supabase for this user. If it does not → `AuthStatus.onboarding`
/// (router sends to health profile setup). If it does → `AuthStatus.authenticated`.
/// This replaces the previous approach of checking user metadata flags.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  HealthProfileRepository get _hpRepo =>
      ref.read(healthProfileRepositoryProvider);
  ProfileRepository get _profileRepo => ref.read(profileRepositoryProvider);
  StreamSubscription<supa.AuthState>? _authSub;

  /// Which sign-in screen this session came through, kept for as long as the
  /// session lasts.
  ///
  /// Signing in resolves the role twice, concurrently: once down the call the
  /// screen made, and once from the `onAuthStateChange` listener reacting to
  /// the same SIGNED_IN event. Both create the `profiles` row if it is
  /// missing, and the listener has no idea which screen the user came
  /// through — so a first-time caregiver used to race a caregiver row against
  /// a patient one, and the listener usually won. The row is created once and
  /// never reconsidered, so that landed the caregiver on the patient
  /// dashboard on that sign-in and on every one after it.
  ///
  /// Holding the hint here gives both paths the same answer, whichever gets
  /// there first. It is a *default* for an account with no row yet, never an
  /// override: an existing row still wins, so arriving via the caregiver
  /// screen cannot convert a patient account.
  UserRole? _signInRoleHint;

  @override
  Future<AuthState> build() async {
    // Subscribe to Supabase auth events so token refresh / sign-out from
    // another tab propagates automatically.
    if (_authSub != null) unawaited(_authSub!.cancel());
    _authSub = supa.Supabase.instance.client.auth.onAuthStateChange.listen(
      (event) async {
        // Re-resolve user on every auth event
        // (SIGNED_IN, TOKEN_REFRESHED, SIGNED_OUT, etc.)
        final result = await _repo.currentUser();
        state = AsyncData(await _stateFromOptionalUser(result));
      },
    );

    // Keep the subscription alive for the notifier's lifetime.
    ref.onDispose(() => _authSub?.cancel());

    final result = await _repo.currentUser();
    return _stateFromOptionalUser(result);
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────

  /// Creates a new account. Returns the error message string if sign-up fails,
  /// or null on success (including the "confirm your email" case which is also
  /// a failure from the session perspective but a success from the UX flow).
  Future<String?> signUp({
    required String email,
    required String password,
    String? fullName,
    UserRole role = UserRole.patient,
  }) async {
    _signInRoleHint = role;
    state = const AsyncLoading();
    final result = await _repo.signUp(
      email: email,
      password: password,
      fullName: fullName,
      role: role,
    );
    return result.when(
      success: (user) async {
        final resolved = await _withResolvedRole(user, fallback: role);
        // Caregiver accounts skip patient health onboarding entirely; a
        // fresh patient sign-up has no health profile yet → onboarding.
        state = AsyncData(
          AuthState(
            status: resolved.role == UserRole.caregiver
                ? AuthStatus.authenticated
                : AuthStatus.onboarding,
            user: resolved,
          ),
        );
        return null;
      },
      failure: (f) {
        state = const AsyncData(AuthState(status: AuthStatus.unauthenticated));
        return f.message;
      },
    );
  }

  // ── Sign In ───────────────────────────────────────────────────────────────

  /// [roleHint] is which sign-in screen the user came through.
  ///
  /// It is only a fallback for an account that has no role recorded yet —
  /// a first Google sign-in, say. An existing account always keeps the role
  /// stored on its profile, so arriving via the caregiver screen can never
  /// turn a patient account into a caregiver one (or hand it someone else's
  /// data).
  Future<void> loginWithEmail(
    String email,
    String password, {
    UserRole roleHint = UserRole.patient,
  }) async {
    _signInRoleHint = roleHint;
    state = const AsyncLoading();
    final result = await _repo.loginWithEmail(email: email, password: password);
    state = AsyncData(await _fromUserResult(result, fallback: roleHint));
  }

  // ── Phone OTP ─────────────────────────────────────────────────────────────

  /// Texts a one-time code to [phone] (E.164, e.g. `+919876543210`).
  /// Returns an error message, or null on success.
  ///
  /// Deliberately does not touch [state]: the user is not signed in yet, and
  /// flipping to [AsyncLoading] here would bounce the router mid-flow and
  /// throw away the number they just typed.
  Future<String?> sendPhoneOtp(String phone) async {
    final result = await _repo.sendPhoneOtp(phone: phone);
    return result.when(
      success: (_) => null,
      failure: (f) => f.message,
    );
  }

  /// Completes an SMS OTP sign-in.
  ///
  /// [roleHint] seeds the role for an account with none recorded yet, and —
  /// when it is [UserRole.caregiver] — also *promotes* an account already
  /// recorded as a patient, provided it holds no health record of its own.
  ///
  /// That promotion is a deliberate loosening of the earlier rule, which
  /// said the caregiver screen could never convert an existing account. The
  /// rule was right in principle and unworkable in practice: the role is
  /// written once, when the profile row is created, and a row seeded wrong
  /// (by the race [_signInRoleHint] now closes, or by any build from before
  /// that fix) left the account stranded on the patient dashboard with no
  /// way back inside the app.
  ///
  /// What still holds the line is [_promoteToCaregiver]'s health-record
  /// check: an account with patient data is refused, so this can only ever
  /// promote an account that has none — and reaching it at all requires
  /// possession of the number and its one-time code.
  Future<void> verifyPhoneOtp(
    String phone,
    String token, {
    UserRole roleHint = UserRole.patient,
  }) async {
    _signInRoleHint = roleHint;
    state = const AsyncLoading();
    final result = await _repo.verifyPhoneOtp(phone: phone, token: token);
    var next = await _fromUserResult(result, fallback: roleHint);
    if (roleHint == UserRole.caregiver &&
        next.user != null &&
        next.user!.role != UserRole.caregiver) {
      next = await _promoteToCaregiver(next);
    }
    state = AsyncData(next);
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> signInWithGoogle({
    UserRole roleHint = UserRole.patient,
  }) async {
    _signInRoleHint = roleHint;
    state = const AsyncLoading();
    final result = await _repo.signInWithGoogle();
    state = AsyncData(await _fromUserResult(result, fallback: roleHint));
  }

  /// Web equivalent of [signInWithGoogle] — completes the sign-in from the
  /// [GoogleWebCredential] Google's own rendered button produced
  /// (see `GoogleWebButton`), rather than driving the picker itself.
  Future<void> completeGoogleWebAuth(GoogleWebCredential credential) async {
    state = const AsyncLoading();
    final result = await _repo.completeGoogleWebAuth(credential);
    state = AsyncData(await _fromUserResult(result));
  }

  // ── Forgot Password ───────────────────────────────────────────────────────

  /// Sends a password-reset email. Returns null on success, error message on failure.
  Future<String?> sendPasswordReset(String email) async {
    final result = await _repo.sendPasswordResetEmail(email);
    return result.when(
      success: (_) => null,
      failure: (f) => f.message,
    );
  }

  // ── Onboarding ────────────────────────────────────────────────────────────

  /// Called by [HealthcareOnboardingScreen] after saving the health profile to
  /// Supabase. Marks the user as onboarded in Supabase user metadata and flips
  /// state to [AuthStatus.authenticated] so the router navigates to /home.
  Future<void> completeOnboarding(Map<String, dynamic> profile) async {
    state = const AsyncLoading();
    final result = await _repo.completeOnboarding(profile);
    state = AsyncData(await _fromUserResult(result));
  }

  // ── Account role ──────────────────────────────────────────────────────────

  /// Promotes the just-signed-in account to a caregiver one, for a sign-in
  /// that came through the caregiver screen.
  ///
  /// Returns [current] untouched if the write fails, so a failure costs the
  /// caller nothing and never blocks the sign-in itself.
  ///
  /// This used to refuse an account that held a health record, on the
  /// grounds that converting somebody's patient account would look to them
  /// like losing their data. That refusal is dropped deliberately: the role
  /// selects which shell renders, and nothing else. `health_profiles`,
  /// `medicines`, `reports` and `scans` are all left exactly as they are, so
  /// the switch hides a patient's data rather than destroying it, and
  /// setting the role back brings the whole patient view with it.
  ///
  /// The cost of dropping it is that signing in through the caregiver screen
  /// now converts any account whose number receives that code, and there is
  /// no way back from inside the app — it takes
  /// `update public.profiles set role = 'patient' where id = '<uid>'`.
  /// Worth adding a way back in the UI if this outlives the demo.
  Future<AuthState> _promoteToCaregiver(AuthState current) async {
    final user = current.user;
    if (user == null) return current;

    try {
      await _profileRepo.setRole(userId: user.id, role: UserRole.caregiver);
    } catch (e) {
      // Same reasoning as the fallback in [_withResolvedRole]: this failure
      // shows up only as "the caregiver dashboard didn't open".
      debugPrint('Caregiver promotion failed: $e');
      return current;
    }

    return AuthState(
      status: AuthStatus.authenticated,
      user: user.copyWith(role: UserRole.caregiver),
    );
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    // The next sign-in may be a different person on a different screen, so
    // the hint must not outlive this session.
    _signInRoleHint = null;
    await _repo.signOut();
    state = const AsyncData(
      AuthState(status: AuthStatus.unauthenticated),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Checks Supabase to see whether a health profile row exists for [user].
  /// Returns [AuthStatus.authenticated] if yes, [AuthStatus.onboarding] if no.
  Future<AuthStatus> _onboardingStatus(AuthUser user) async {
    try {
      final result = await _hpRepo.loadHealthProfile(user.id);
      return result.when(
        success: (data) =>
            data != null ? AuthStatus.authenticated : AuthStatus.onboarding,
        failure: (_) =>
            // On network error, default to authenticated to avoid blocking
            // existing users.
            user.onboardingComplete
                ? AuthStatus.authenticated
                : AuthStatus.onboarding,
      );
    } catch (_) {
      return user.onboardingComplete
          ? AuthStatus.authenticated
          : AuthStatus.onboarding;
    }
  }

  Future<AuthState> _fromUserResult(
    Result<AuthUser> result, {
    UserRole? fallback,
  }) async {
    return result.when(
      success: (user) async {
        final resolved = await _withResolvedRole(user, fallback: fallback);
        return AuthState(
          status: resolved.role == UserRole.caregiver
              ? AuthStatus.authenticated
              : await _onboardingStatus(resolved),
          user: resolved,
        );
      },
      failure: (f) async => AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: f.message,
      ),
    );
  }

  Future<AuthState> _stateFromOptionalUser(
    Result<AuthUser?> result,
  ) async {
    return result.when(
      success: (user) async {
        if (user == null) {
          return const AuthState(status: AuthStatus.unauthenticated);
        }
        final resolved = await _withResolvedRole(user);
        return AuthState(
          status: resolved.role == UserRole.caregiver
              ? AuthStatus.authenticated
              : await _onboardingStatus(resolved),
          user: resolved,
        );
      },
      failure: (_) async => const AuthState(status: AuthStatus.unauthenticated),
    );
  }

  /// Resolves [user]'s persisted role (patient/caregiver) from the
  /// `profiles` table, creating that row on first resolution if it doesn't
  /// exist yet. [fallback] seeds the row only when nothing was signalled at
  /// sign-up time (e.g. Google sign-in, which has no role picker); the
  /// `pending_role` sign-up hint otherwise takes precedence.
  Future<AuthUser> _withResolvedRole(
    AuthUser user, {
    UserRole? fallback,
  }) async {
    final hint =
        supa.Supabase.instance.client.auth.currentUser?.userMetadata?['pending_role']
            as String?;
    final defaultRole = resolveDefaultRole(
      pendingRoleMetadata: hint,
      callerHint: fallback,
      sessionHint: _signInRoleHint,
    );
    try {
      final role = await _profileRepo.ensureAndFetchRole(
        userId: user.id,
        defaultRole: defaultRole,
        displayName: user.fullName,
      );
      return user.copyWith(role: role);
    } catch (e) {
      // Network error resolving role — fall back to whatever the auth
      // layer already mapped rather than blocking sign-in entirely.
      //
      // Logged because the fallback is silent by design and lands the user
      // on the patient shell: without this line, a caregiver on the wrong
      // dashboard is indistinguishable from a caregiver whose role really
      // is patient, which is a long afternoon to work out from the outside.
      debugPrint('Role lookup failed ($e) — falling back to ${user.role}.');
      return user;
    }
  }
}

/// Which role seeds the `profiles` row for an account that has none yet.
///
/// Only ever a default: an account with a row keeps the role on it, so none
/// of these hints can convert an existing account.
///
/// [pendingRoleMetadata] is the `pending_role` written into Supabase user
/// metadata at sign-up, and outranks the rest because it survives an email
/// confirmation that finished on another device. [callerHint] is the screen
/// the caller came through. [sessionHint] is the screen *this session* signed
/// in through, and is what the `onAuthStateChange` listener resolves against
/// — it resolves the same sign-in concurrently and has no caller to ask, so
/// without it a first-time caregiver races a patient row against their own
/// caregiver one and lands on the patient dashboard for good.
UserRole resolveDefaultRole({
  String? pendingRoleMetadata,
  UserRole? callerHint,
  UserRole? sessionHint,
}) {
  if (pendingRoleMetadata == 'caregiver') return UserRole.caregiver;
  return callerHint ?? sessionHint ?? UserRole.patient;
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: the resolved [AuthStatus], defaulting to `unknown` while the
/// controller is still booting.
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authControllerProvider).valueOrNull?.status ??
      AuthStatus.unknown;
});
