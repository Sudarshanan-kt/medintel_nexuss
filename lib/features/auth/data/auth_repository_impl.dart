import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Hide supabase_flutter's AuthUser to avoid name conflict with our domain AuthUser.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_auth_config.dart';
import '../../../core/errors/failure.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/result.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// [AuthRepository] backed by Supabase Auth.
///
/// All network calls go through the Supabase Flutter SDK — the Dio client
/// is kept only for backend API requests (scans, reports, etc.).
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._storage, this._supabase);

  final FlutterSecureStorage _storage;
  final SupabaseClient _supabase;

  // ── currentUser ──────────────────────────────────────────────────────────

  @override
  Future<Result<AuthUser?>> currentUser() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) return const Success(null);
      final supaUser = _supabase.auth.currentUser;
      if (supaUser == null) return const Success(null);
      return Success(_mapSupaUser(supaUser));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  // ── signUp ───────────────────────────────────────────────────────────────

  @override
  Future<Result<AuthUser>> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final res = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: fullName != null && fullName.trim().isNotEmpty
            ? {'full_name': fullName.trim()}
            : null,
      );
      final supaUser = res.user;
      if (supaUser == null) {
        // Email confirmation required — account created but no session yet.
        return const ResultFailure(
          AuthFailure(
            'Account created! Please check your email and confirm your address before signing in.',
          ),
        );
      }
      await _cacheOnboardingFlag(supaUser);
      return Success(_mapSupaUser(supaUser));
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  // ── loginWithEmail ────────────────────────────────────────────────────────

  @override
  Future<Result<AuthUser>> loginWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final supaUser = res.user;
      if (supaUser == null) {
        return const ResultFailure(
          AuthFailure('Sign-in failed. Please try again.'),
        );
      }
      await _cacheOnboardingFlag(supaUser);
      return Success(_mapSupaUser(supaUser));
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  // ── signInWithGoogle ─────────────────────────────────────────────────────

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    if (!GoogleAuthConfig.isConfigured) {
      // Fail loudly-but-politely instead of letting the native SDK throw an
      // opaque "developer error" — same posture as Apple Sign-In's
      // not-set-up message elsewhere in this flow.
      return const ResultFailure(
        AuthFailure(
          'Google Sign-In isn’t set up yet. Use email for now, or ask your '
          'developer to add GOOGLE_WEB_CLIENT_ID (see .env.example).',
        ),
      );
    }
    try {
      // One "Web application" OAuth client covers every platform here:
      // web reads it as its own client ID, native platforms pass it as
      // serverClientId so the ID token's audience is the one Supabase's
      // Google provider is configured to trust.
      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? GoogleAuthConfig.webClientId : null,
        serverClientId: kIsWeb ? null : GoogleAuthConfig.webClientId,
      );
      // The web popup flow can hang indefinitely with no resolve/reject at
      // all if the popup itself never opens (e.g. blocked by the browser) —
      // a bare `await` here would leave the sign-in button spinning forever
      // with no way out. A timeout turns that into a clear, recoverable error.
      final googleUser = await googleSignIn.signIn().timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException('Google sign-in timed out'),
      );
      if (googleUser == null) {
        // User cancelled the picker.
        return const ResultFailure(
          AuthFailure('Google sign-in was cancelled.'),
        );
      }
      final googleAuth = await googleUser.authentication;
      return _completeGoogleAuth(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
    } on TimeoutException {
      return const ResultFailure(
        AuthFailure(
          'Google sign-in didn’t respond — check that pop-ups aren’t '
          'blocked for this site, then try again.',
        ),
      );
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  @override
  Future<Result<AuthUser>> completeGoogleWebAuth(
    GoogleWebCredential credential,
  ) async {
    try {
      return await _completeGoogleAuth(
        idToken: credential.idToken,
        nonce: credential.nonce,
      );
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  /// Shared tail of both Google flows: exchange a Google ID token for a
  /// Supabase session.
  ///
  /// [nonce] must be the same raw nonce that was used to request [idToken]
  /// whenever that token actually carries a `nonce` claim — Supabase hashes
  /// it and compares against the claim, and rejects the exchange if only one
  /// side is present. Native mobile sign-in never sets a nonce on the token
  /// it requests, so it's fine left null there; the web button always does
  /// (see [GoogleWebCredential]), so it must always pass one.
  Future<Result<AuthUser>> _completeGoogleAuth({
    required String? idToken,
    String? accessToken,
    String? nonce,
  }) async {
    if (idToken == null) {
      return const ResultFailure(
        AuthFailure('Could not get Google credentials. Please try again.'),
      );
    }
    final res = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
      nonce: nonce,
    );
    final supaUser = res.user;
    if (supaUser == null) {
      return const ResultFailure(
        AuthFailure('Google sign-in failed. Please try again.'),
      );
    }
    await _cacheOnboardingFlag(supaUser);
    return Success(_mapSupaUser(supaUser));
  }

  // ── sendPasswordResetEmail ────────────────────────────────────────────────

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim());
      return const Success(null);
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  // ── completeOnboarding ────────────────────────────────────────────────────

  @override
  Future<Result<AuthUser>> completeOnboarding(
    Map<String, dynamic> profile,
  ) async {
    try {
      final name = profile['fullName'] as String?;
      // Update Supabase user metadata so the name persists server-side.
      final res = await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            if (name != null && name.trim().isNotEmpty)
              'full_name': name.trim(),
            'onboarding_complete': true,
          },
        ),
      );
      final supaUser = res.user;
      if (supaUser == null) {
        return const ResultFailure(AuthFailure('Failed to save profile.'));
      }
      // Cache locally so offline cold boots restore the flag.
      await _storage.write(
        key: AppConstants.kOnboardingComplete,
        value: 'true',
      );
      if (name != null && name.trim().isNotEmpty) {
        await _storage.write(key: AppConstants.kUserName, value: name.trim());
      }
      return Success(_mapSupaUser(supaUser, forceOnboarded: true));
    } on AuthException catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.message)));
    } catch (e) {
      return ResultFailure(AuthFailure(_friendlyAuthMessage(e.toString())));
    }
  }

  // ── signOut ───────────────────────────────────────────────────────────────

  @override
  Future<Result<void>> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Best-effort — still clear local state even if the network call fails.
    }
    // Clear only the session/identity keys. The patient's profile + medical
    // record (mn_profile_*) is intentionally preserved so it remains intact
    // across logout/login on the same device.
    await _storage.delete(key: AppConstants.kOnboardingComplete);
    await _storage.delete(key: AppConstants.kUserName);
    return const Success(null);
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Maps a Supabase [User] to the domain [AuthUser].
  AuthUser _mapSupaUser(User supaUser, {bool forceOnboarded = false}) {
    final meta = supaUser.userMetadata ?? <String, dynamic>{};
    final appMeta = supaUser.appMetadata;
    final fullName = (meta['full_name'] as String?)?.trim();
    final onboardedMeta = meta['onboarding_complete'] as bool? ?? false;
    // Consider onboarding done when the full name is set OR the flag is true.
    final onboardingComplete = forceOnboarded ||
        onboardedMeta ||
        (fullName != null && fullName.isNotEmpty);

    final roleStr = appMeta['role'] as String?;
    final role = _mapRole(roleStr);

    return AuthUser(
      id: supaUser.id,
      role: role,
      onboardingComplete: onboardingComplete,
      fullName: fullName?.isEmpty == true ? null : fullName,
      email: supaUser.email,
      avatarUrl: meta['avatar_url'] as String?,
    );
  }

  /// Caches the onboarding flag locally so cold boots are instant.
  Future<void> _cacheOnboardingFlag(User supaUser) async {
    final meta = supaUser.userMetadata ?? <String, dynamic>{};
    final fullName = (meta['full_name'] as String?)?.trim();
    final onboardedMeta = meta['onboarding_complete'] as bool? ?? false;
    final onboarded =
        onboardedMeta || (fullName != null && fullName.isNotEmpty);
    await _storage.write(
      key: AppConstants.kOnboardingComplete,
      value: onboarded ? 'true' : 'false',
    );
    if (fullName != null && fullName.isNotEmpty) {
      await _storage.write(key: AppConstants.kUserName, value: fullName);
    }
  }

  UserRole _mapRole(String? role) {
    switch (role) {
      case 'doctor':
      case 'clinician':
        return UserRole.clinician;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.patient;
    }
  }

  /// Returns a user-friendly message for common Supabase auth errors.
  String _friendlyAuthMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email address before signing in.';
    }
    if (lower.contains('user already registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (lower.contains('password should be at least')) {
      return 'Password must be at least 8 characters.';
    }
    if (lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (lower.contains('network') || lower.contains('connection')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (lower.contains('empty response') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('httpexception') ||
        lower.contains('timeout')) {
      return 'Could not reach the server. Please check your connection and try again.';
    }
    // Any other exception (auth-provider config errors, unexpected SDK
    // failures) — never leak raw exception text/stack traces to the UI.
    if (lower.contains('exception') || lower.contains('error:')) {
      return 'Something went wrong. Please try again in a moment.';
    }
    return raw;
  }
}

/// Convenience provider for the Supabase client singleton.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// DI: binds the [AuthRepository] interface to its implementation.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    ref.watch(secureStorageProvider),
    ref.watch(supabaseClientProvider),
  ),
);
