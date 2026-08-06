/// The role a signed-in user holds. Drives which shell (patient vs clinic
/// vs caregiver) and feature set the app renders.
enum UserRole { patient, caregiver, clinician, admin }

/// Immutable domain entity for an authenticated user.
///
/// Plain Dart (no Flutter import) — the domain layer is framework-agnostic.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.role,
    required this.onboardingComplete,
    this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
  });

  final String id;
  final UserRole role;
  final bool onboardingComplete;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;

  /// Display name fallback chain.
  String get displayName => fullName ?? email ?? phone ?? 'there';

  AuthUser copyWith({
    String? fullName,
    String? avatarUrl,
    bool? onboardingComplete,
    UserRole? role,
  }) {
    return AuthUser(
      id: id,
      role: role ?? this.role,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      fullName: fullName ?? this.fullName,
      phone: phone,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
