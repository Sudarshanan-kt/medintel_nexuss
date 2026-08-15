import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/data/demo_otp_repository.dart';
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

/// Stands in for the table the Send SMS hook writes to.
class _FakeDemoOtpRepository implements DemoOtpRepository {
  static final codes = <String, String>{};

  @override
  Future<String?> latestCodeFor(String phoneE164) async =>
      codes[phoneE164.trim()];
}

Future<void> _pump(WidgetTester tester) async {
  _FakeAuthController.reset();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        demoOtpRepositoryProvider.overrideWithValue(_FakeDemoOtpRepository()),
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

  group('demo sign-in shows the code instead of texting it', () {
    tearDown(() {
      dotenv.clean();
      _FakeDemoOtpRepository.codes.clear();
    });

    testWidgets(
        'the code step prints what Auth generated, and says no text '
        'was sent', (tester) async {
      dotenv.testLoad(fileInput: 'DEMO_OTP_ON_SCREEN=true');
      _FakeDemoOtpRepository.codes['+919876543210'] = '424242';
      await _pump(tester);

      // The first step should already stop promising a text message.
      expect(find.text('Show my code'), findsOneWidget);
      expect(find.text('Text me a code'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, '9876543210');
      await tester.tap(find.text('Show my code'));
      await tester.pumpAndSettle();

      expect(find.text('424242'), findsOneWidget);
      expect(find.text('Demo sign-in — no text message sent'), findsOneWidget);
      expect(find.textContaining('We texted'), findsNothing);
      // Still a real send — Auth generates and checks the code either way.
      expect(_FakeAuthController.calls, ['send:+919876543210']);
    });

    testWidgets('a resend shows the new code, not the old one', (tester) async {
      // The whole point of the hook over a fixed test OTP: Auth generates a
      // fresh code per send, and the screen must not keep showing the last.
      dotenv.testLoad(fileInput: 'DEMO_OTP_ON_SCREEN=true');
      _FakeDemoOtpRepository.codes['+919876543210'] = '111111';
      await _pump(tester);

      await tester.enterText(find.byType(TextFormField).first, '9876543210');
      await tester.tap(find.text('Show my code'));
      await tester.pumpAndSettle();
      expect(find.text('111111'), findsOneWidget);

      _FakeDemoOtpRepository.codes['+919876543210'] = '222222';
      await tester.pump(const Duration(seconds: 61)); // clear the cooldown
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();

      expect(find.text('222222'), findsOneWidget);
      expect(find.text('111111'), findsNothing);
    });

    testWidgets('an unreadable code says so rather than showing a blank',
        (tester) async {
      // No text message is coming, so an empty banner would leave the
      // caregiver with nothing at all and no way to know why.
      dotenv.testLoad(fileInput: 'DEMO_OTP_ON_SCREEN=true');
      await _pump(tester);

      await tester.enterText(find.byType(TextFormField).first, '9876543210');
      await tester.tap(find.text('Show my code'));
      await tester.pumpAndSettle();

      expect(find.text('Reading the code…'), findsOneWidget);

      // Drain the retry's delay: a miss schedules one more lookup, and a
      // Future.delayed still in flight fails the test on teardown.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('Reading the code…'), findsOneWidget);
    });

    testWidgets('off by default: the SMS flow is untouched', (tester) async {
      dotenv.testLoad(fileInput: 'DEMO_OTP_ON_SCREEN=');
      await _pump(tester);

      expect(find.text('Text me a code'), findsOneWidget);
      await _submitPhone(tester, '9876543210');

      expect(find.textContaining('We texted'), findsOneWidget);
      expect(find.text('Demo sign-in — no text message sent'), findsNothing);
    });
  });

  testWidgets('the backdrop motifs reach the bottom of a tall screen',
      (tester) async {
    // The screen is shorter than a phone, so the Stack's scroll view — its
    // only unpositioned child — shrink-wraps unless the body is forced to
    // expand. When it does, Positioned.fill fills the *content* rather than
    // the screen: the lower motifs collect just under the card and the whole
    // bottom third of the page is bare.
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester);

    final motif = find.byWidgetPredicate(
      (w) => w is Icon && w.icon == Icons.calendar_month_rounded,
    );
    expect(motif, findsOneWidget);
    // Placed at Alignment(_, 0.80) — it belongs near the bottom edge, not
    // wherever the content happens to end.
    expect(tester.getCenter(motif).dy, greaterThan(700));
  });
}
