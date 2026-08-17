import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';

/// Signing in resolves the account's role twice at once: down the call the
/// sign-in screen made, and from the `onAuthStateChange` listener reacting to
/// the same SIGNED_IN event. Whichever gets there first creates the
/// `profiles` row, and that row is never reconsidered — so the two paths
/// disagreeing is not a transient glitch but a caregiver permanently landing
/// on the patient dashboard.
void main() {
  group('default role for an account with no profile row yet', () {
    test('the listener seeds caregiver when the session signed in as one', () {
      // The listener's view of a caregiver sign-in: no caller to ask, only
      // the session hint. This is the case that used to seed 'patient'.
      expect(
        resolveDefaultRole(sessionHint: UserRole.caregiver),
        UserRole.caregiver,
      );
    });

    test('caller and session agree on a caregiver sign-in', () {
      expect(
        resolveDefaultRole(
          callerHint: UserRole.caregiver,
          sessionHint: UserRole.caregiver,
        ),
        UserRole.caregiver,
      );
    });

    test('a patient sign-in stays patient on both paths', () {
      expect(resolveDefaultRole(sessionHint: UserRole.patient), UserRole.patient);
      expect(
        resolveDefaultRole(callerHint: UserRole.patient),
        UserRole.patient,
      );
    });

    test('nothing signalled at all falls back to patient', () {
      expect(resolveDefaultRole(), UserRole.patient);
    });

    test('the sign-up metadata hint outranks the screen hints', () {
      // Survives an email confirmation finished on another device, where
      // neither hint is available on the machine that completes sign-in.
      expect(
        resolveDefaultRole(
          pendingRoleMetadata: 'caregiver',
          callerHint: UserRole.patient,
          sessionHint: UserRole.patient,
        ),
        UserRole.caregiver,
      );
    });

    test('an unrecognised metadata value does not silently grant caregiver', () {
      expect(resolveDefaultRole(pendingRoleMetadata: 'clinician'), UserRole.patient);
      expect(resolveDefaultRole(pendingRoleMetadata: ''), UserRole.patient);
    });
  });
}
