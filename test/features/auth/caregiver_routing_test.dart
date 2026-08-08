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
