import '../../../core/utils/result.dart';
import 'auth_user.dart';

/// An ID token credential from Google's own rendered web button, plus the
/// raw nonce used to request it.
///
/// Google's web SDK embeds a `nonce` claim in the ID token whenever FedCM is
/// used (which it now is, by default), so Supabase's `signInWithIdToken`
/// requires that same raw nonce be passed alongside the token or it rejects
/// the exchange with "Passed nonce and nonce in id_token should either both
/// exist or not." The `google_sign_in`/`google_sign_in_web` plugins never
/// surface this nonce, so the web button drives Google's identity-services
/// JS API directly (see `google_web_button_web.dart`) instead of going
/// through `GoogleSignIn().signIn()` — hence this separate credential type
/// rather than reusing `GoogleSignInAuthentication`.
class GoogleWebCredential {
  const GoogleWebCredential({required this.idToken, required this.nonce});

  final String idToken;
  final String nonce;
}

/// Contract the data layer must satisfy. The domain layer owns this
/// interface; `data/auth_repository_impl.dart` implements it against
/// the Supabase SDK.
abstract interface class AuthRepository {
  /// Returns the currently persisted Supabase session user, if any (offline-first boot).
  Future<Result<AuthUser?>> currentUser();

  /// Creates a new account with [email] + [password] and optional [fullName].
  /// [role] is stashed in Supabase auth metadata as `pending_role` so it
  /// survives even the "confirm your email first" path, where no session
  /// exists yet to write it to the `profiles` table.
  /// Supabase may send a confirmation email depending on project settings.
  Future<Result<AuthUser>> signUp({
    required String email,
    required String password,
    String? fullName,
    UserRole role = UserRole.patient,
  });

  /// Signs in an existing user with [email] + [password].
  Future<Result<AuthUser>> loginWithEmail({
    required String email,
    required String password,
  });

  /// Signs in (or up) via Google OAuth using native Google Sign-In.
  /// Returns the authenticated [AuthUser] on success.
  ///
  /// Mobile-only in practice: the web popup flow this drives can't reliably
  /// return an ID token (see [completeGoogleWebAuth] for web's equivalent).
  Future<Result<AuthUser>> signInWithGoogle();

  /// Completes a Google sign-in on web, given the [GoogleWebCredential]
  /// produced by Google's own rendered button (see `GoogleWebButton`) —
  /// the only web flow that reliably includes an ID token.
  Future<Result<AuthUser>> completeGoogleWebAuth(
    GoogleWebCredential credential,
  );

  /// Sends a password-reset email to [email].
  /// Returns [Success(null)] on dispatch; the actual reset happens via link.
  Future<Result<void>> sendPasswordResetEmail(String email);

  /// Persists the patient health profile and flips `onboardingComplete`.
  Future<Result<AuthUser>> completeOnboarding(Map<String, dynamic> profile);

  /// Signs out the current user from Supabase and clears local cache.
  Future<Result<void>> signOut();
}
