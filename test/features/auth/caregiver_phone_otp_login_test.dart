import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';
import 'package:medintel_nexus/features/auth/presentation/caregiver_login_screen.dart';

/// Records the OTP calls the screen makes, and lets a test force a failure.
class _FakeAuthController extends AuthController {
  static final calls = <String>[];
  static String? sendError;
  static String? verifyError;

  static void reset() {
    calls.clear();
    sendError = null;
    verifyError = null;
  }

  @override
  Future<AuthState> build() async =>
      const AuthState(status: AuthStatus.unauthenticated);

  @override
  Future<String?> sendPhoneOtp(String phone) async {
    calls.add('send:${phone.trim()}');
    return sendError;
  }

  @override
  Future<void> verifyPhoneOtp(
    String phone,
    String token, {
    UserRole roleHint = UserRole.patient,
  }) async {
    calls.add('verify:${phone.trim()}:$token:role=${roleHint.name}');
    if (verifyError != null) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: verifyError,
        ),
      );
    }
  }
}

Future<void> _pump(WidgetTester tester) async {
  _FakeAuthController.reset();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
      child: const MaterialApp(home: CaregiverLoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _submitPhone(WidgetTester tester, String phone) async {
  await tester.enterText(find.byType(TextFormField).first, phone);
  await tester.tap(find.text('Text me a code'));
  await tester.pumpAndSettle();
}

void main() {
  group('caregivers sign in with a code, never a password', () {
    testWidgets('the first step asks only for a mobile number', (tester) async {
      await _pump(tester);

      expect(find.text('Text me a code'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      // The things that used to be here and must not come back.
      expect(find.text('Password'), findsNothing);
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Sign in as caregiver'), findsNothing);
      expect(
        find.textContaining("No password needed"),
        findsOneWidget,
      );
    });

    testWidgets('a malformed number never reaches the server', (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '12');

      expect(_FakeAuthController.calls, isEmpty);
      expect(find.text('Text me a code'), findsOneWidget);
    });

    testWidgets('a valid number sends a code and moves to the code step',
        (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');

      expect(_FakeAuthController.calls, ['send:+919876543210']);
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.textContaining('9876543210'), findsOneWidget);
    });

    testWidgets('a send failure keeps the user on the number step',
        (tester) async {
      await _pump(tester);
      _FakeAuthController.sendError = 'Too many attempts.';
      await _submitPhone(tester, '9876543210');

      expect(find.text('Too many attempts.'), findsOneWidget);
      expect(find.text('Enter your code'), findsNothing);
    });

    testWidgets('the code is verified with the caregiver role hint',
        (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');

      await tester.enterText(find.byType(TextFormField).first, '123456');
      await tester.tap(find.text('Sign in as caregiver'));
      await tester.pumpAndSettle();

      expect(
        _FakeAuthController.calls.last,
        'verify:+919876543210:123456:role=caregiver',
      );
    });

    testWidgets('a short code is refused before any network call',
        (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');
      _FakeAuthController.calls.clear();

      await tester.enterText(find.byType(TextFormField).first, '123');
      await tester.tap(find.text('Sign in as caregiver'));
      await tester.pumpAndSettle();

      expect(_FakeAuthController.calls, isEmpty);
      expect(find.text('Enter the 6-digit code.'), findsOneWidget);
    });

    testWidgets('a rejected code is reported', (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');
      _FakeAuthController.verifyError =
          'That code has expired or is incorrect. Request a new one.';

      await tester.enterText(find.byType(TextFormField).first, '000000');
      await tester.tap(find.text('Sign in as caregiver'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('expired or is incorrect'),
        findsOneWidget,
      );
    });
  });

  group('resend', () {
    // Supabase rate-limits repeat sends; the button counts down rather than
    // letting the user press it into an error.
    testWidgets('is on cooldown immediately after a send', (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');

      expect(find.textContaining('Resend in'), findsOneWidget);
      expect(find.text('Resend code'), findsNothing);
    });

    testWidgets('becomes available once the cooldown elapses', (tester) async {
      await _pump(tester);
      await _submitPhone(tester, '9876543210');

      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(find.text('Resend code'), findsOneWidget);

      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(_FakeAuthController.calls, hasLength(2));
    });
  });

  testWidgets('a leading zero is stripped before sending', (tester) async {
    // Indian numbers are often written "09876543210", but E.164 has no
    // trunk prefix and Supabase rejects the number outright with it.
    await _pump(tester);
    await _submitPhone(tester, '09876543210');

    expect(_FakeAuthController.calls, ['send:+919876543210']);
  });

  testWidgets('spaces and dashes are stripped before sending', (tester) async {
    await _pump(tester);
    await _submitPhone(tester, '98765-43210');

    expect(_FakeAuthController.calls, ['send:+919876543210']);
  });

  testWidgets('changing the number returns to the first step', (tester) async {
    await _pump(tester);
    await _submitPhone(tester, '9000000000');

    await tester.tap(find.text('Change number'));
    await tester.pumpAndSettle();

    expect(find.text('Text me a code'), findsOneWidget);
    expect(find.text('Enter your code'), findsNothing);
  });
}
