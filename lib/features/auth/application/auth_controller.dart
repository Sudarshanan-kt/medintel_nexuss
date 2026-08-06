import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../core/utils/result.dart';
import '../../profile/data/health_profile_repository.dart';
import '../data/auth_repository_impl.dart';
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
  StreamSubscription<supa.AuthState>? _authSub;

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
  }) async {
    state = const AsyncLoading();
    final result = await _repo.signUp(
      email: email,
      password: password,
      fullName: fullName,
    );
    return result.when(
      success: (user) async {
        // New sign-up → no health profile exists → onboarding.
        state = AsyncData(
          AuthState(
            status: AuthStatus.onboarding,
            user: user,
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

  Future<void> loginWithEmail(String email, String password) async {
    state = const AsyncLoading();
    final result = await _repo.loginWithEmail(email: email, password: password);
    state = AsyncData(await _fromUserResult(result));
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    final result = await _repo.signInWithGoogle();
    state = AsyncData(await _fromUserResult(result));
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

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
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

  Future<AuthState> _fromUserResult(Result<AuthUser> result) async {
    return result.when(
      success: (user) async => AuthState(
        status: await _onboardingStatus(user),
        user: user,
      ),
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
        return AuthState(
          status: await _onboardingStatus(user),
          user: user,
        );
      },
      failure: (_) async => const AuthState(status: AuthStatus.unauthenticated),
    );
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: the resolved [AuthStatus], defaulting to `unknown` while the
/// controller is still booting.
final authStatusProvider = Provider<AuthStatus>((ref) {
  return ref.watch(authControllerProvider).valueOrNull?.status ??
      AuthStatus.unknown;
});
