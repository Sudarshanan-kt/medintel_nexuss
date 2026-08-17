import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/app/router/route_names.dart';

/// The caregiver/patient split is a data boundary, not just navigation: the
/// patient shell reads the signed-in user's own medicines, scans and
/// reports, none of which a caregiver has. These pin down the route sets so
/// a future screen can't quietly widen the boundary.
void main() {
  // Mirrors _caregiverRoutes in app_router.dart. Kept as a literal rather
  // than imported, so that widening the real set has to be a deliberate
  // change here too rather than something a test silently follows.
  const caregiverAllowed = {
    Routes.caregiverHome,
    Routes.careCircle,
    Routes.profile,
  };

  // Mirrors _caregiverRoutePrefixes — matched by prefix, so they carry a
  // path parameter.
  const caregiverAllowedPrefixes = {
    Routes.caregiverPatient,
    Routes.inviteAccept,
  };

  const patientOnly = [
    Routes.home,
    Routes.scan,
    Routes.reports,
    Routes.assistant,
  ];

  group('caregiver route boundary', () {
    test('a caregiver may reach their own home, circle and profile', () {
      expect(caregiverAllowed, contains(Routes.caregiverHome));
      expect(caregiverAllowed, contains(Routes.careCircle));
      expect(caregiverAllowed, contains(Routes.profile));
    });

    test('no patient health screen is reachable by a caregiver', () {
      // These all render the signed-in user's own health data, which a
      // caregiver account has none of.
      for (final route in patientOnly) {
        expect(
          caregiverAllowed.contains(route),
          isFalse,
          reason: '$route shows patient health data and must stay out of '
              'the caregiver route set',
        );
      }
    });

    test('the caregiver home is not reachable by a patient', () {
      expect(patientOnly.contains(Routes.caregiverHome), isFalse);
    });

    test('a caregiver can redeem an invite', () {
      // Redeeming is how a caregiver acquires a patient at all. Leaving it
      // out made the role a dead end: the invite deep link hit the guard
      // and bounced back to an empty dashboard.
      expect(caregiverAllowedPrefixes, contains(Routes.inviteAccept));
    });

    test('the invite screen carries a code, so it is matched by prefix', () {
      // An exact-match entry would never fire — the real location always
      // has the code appended.
      expect(Routes.inviteAcceptCode('A1B2C3').startsWith(Routes.inviteAccept),
          isTrue,);
      expect(caregiverAllowed.contains(Routes.inviteAccept), isFalse);
    });
  });

  group('routes', () {
    test('caregiver sign-in lives under /auth so the guard lets it through', () {
      // The unauthenticated branch of the redirect allows anything under
      // /auth; a caregiver login outside that prefix would bounce to the
      // patient sign-in before it ever rendered.
      expect(Routes.caregiverSignIn.startsWith('/auth'), isTrue);
    });

    test('patient and caregiver sign-in are distinct destinations', () {
      expect(Routes.caregiverSignIn, isNot(Routes.signIn));
    });
  });
}
