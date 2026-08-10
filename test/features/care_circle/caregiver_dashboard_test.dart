import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';
import 'package:medintel_nexus/features/care_circle/application/care_circle_controller.dart';
import 'package:medintel_nexus/features/care_circle/application/care_task_controller.dart';
import 'package:medintel_nexus/features/care_circle/domain/care_circle_models.dart';
import 'package:medintel_nexus/features/care_circle/presentation/caregiver_dashboard_screen.dart';
import 'package:medintel_nexus/features/reminders/adherence_controller.dart';
import 'package:medintel_nexus/features/reminders/domain/medicine.dart';

class _FakeAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
        status: AuthStatus.authenticated,
        user: AuthUser(
          id: 'c1',
          role: UserRole.caregiver,
          onboardingComplete: true,
          fullName: 'Asha Menon',
        ),
      );
}

class _FakeCareCircleController extends CareCircleController {
  _FakeCareCircleController(this.seed);
  final CareCircleState seed;

  @override
  CareCircleState build() => seed;
}

CareCircleMember _member({String name = 'Grandma Rosa', String id = 'p1'}) =>
    CareCircleMember(
      id: 'm_$id',
      patientId: id,
      patientDisplayName: name,
      caregiverId: 'c1',
      caregiverDisplayName: 'Asha Menon',
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

/// Logs producing a known weekly percentage: 3 taken, 2 missed = 60%.
List<DoseLog> _logsAt60Percent() {
  final today = DateTime.now();
  return [
    for (var i = 0; i < 3; i++)
      DoseLog(
        id: 'taken_$i',
        medicineId: 'med1',
        medicineName: 'Metformin',
        dosage: '500mg',
        scheduleSlot: 'morning',
        timestamp: today.subtract(Duration(days: i)),
        status: 'taken',
      ),
    for (var i = 0; i < 2; i++)
      DoseLog(
        id: 'missed_$i',
        medicineId: 'med2',
        medicineName: 'Amlodipine',
        dosage: '5mg',
        scheduleSlot: 'night',
        timestamp: today.subtract(Duration(days: i)),
        status: 'missed',
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  CareCircleState state, {
  GoRouter? router,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        careCircleControllerProvider
            .overrideWith(() => _FakeCareCircleController(state)),
        // The board fetches over the network; these tests are about the
        // dashboard around it.
        careTasksProvider.overrideWith((ref, arg) async => <CareTask>[]),
      ],
      child: router == null
          ? const MaterialApp(home: CaregiverDashboardScreen())
          : MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a failed load is never shown as an empty circle', () {
    // The bug this guards: the screen checked `patients.isEmpty` before it
    // checked `error`, so a network failure rendered "You're not caring for
    // anyone yet" — telling a caregiver their circle is empty when the app
    // simply could not reach the server.
    testWidgets('shows the failure, not the empty state', (tester) async {
      await _pump(
        tester,
        const CareCircleState(
          linkedPatients: [],
          error: 'Could not load your care circle. Check your connection.',
        ),
      );

      expect(find.text("Couldn't load your circle"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining("You're not caring for anyone"), findsNothing);
    });

    testWidgets('says plainly that silence is not good news', (tester) async {
      await _pump(
        tester,
        const CareCircleState(linkedPatients: [], error: 'Offline.'),
      );

      expect(
        find.textContaining("doesn't mean anything is wrong"),
        findsOneWidget,
      );
    });

    testWidgets('a genuinely empty circle still shows the empty state',
        (tester) async {
      await _pump(tester, const CareCircleState(linkedPatients: []));

      expect(find.text("Couldn't load your circle"), findsNothing);
      expect(find.text("You're not caring for anyone yet."), findsOneWidget);
    });
  });

  group('patient card', () {
    testWidgets('states the adherence in words, not only in colour',
        (tester) async {
      await _pump(
        tester,
        CareCircleState(
          linkedPatients: [
            LinkedPatientView(
              member: _member(),
              adherence: computeAdherenceState(_logsAt60Percent()),
              logs: _logsAt60Percent(),
            ),
          ],
        ),
      );

      expect(find.text('60%'), findsOneWidget);
      // 60% falls in the middle band; the word must accompany the colour so
      // the state is legible without colour vision.
      expect(find.textContaining('Slipping'), findsOneWidget);
    });

    testWidgets('opens the patient detail screen when tapped', (tester) async {
      final patients = [
        LinkedPatientView(
          member: _member(),
          adherence: computeAdherenceState(_logsAt60Percent()),
          logs: _logsAt60Percent(),
        ),
      ];

      final router = GoRouter(
        initialLocation: '/caregiver-home',
        routes: [
          GoRoute(
            path: '/caregiver-home',
            builder: (_, __) => const CaregiverDashboardScreen(),
          ),
          GoRoute(
            path: '/caregiver-home/patient/:patientId',
            builder: (_, s) =>
                Scaffold(body: Text('detail:${s.pathParameters['patientId']}')),
          ),
        ],
      );

      await _pump(tester, CareCircleState(linkedPatients: patients),
          router: router,);

      await tester.tap(find.text('Grandma Rosa'));
      await tester.pumpAndSettle();

      expect(find.text('detail:p1'), findsOneWidget);
    });
  });

  group('quick actions', () {
    // The tile here used to be "Emergency", wired to `tel:` with no number
    // in it. It could not dial anyone.
    testWidgets('offers no Emergency button that cannot work', (tester) async {
      await _pump(
        tester,
        CareCircleState(
          linkedPatients: [
            LinkedPatientView(
              member: _member(),
              adherence: AdherenceState.empty,
            ),
          ],
        ),
      );

      expect(find.text('Emergency'), findsNothing);
      expect(find.text('Ask for help'), findsOneWidget);
    });
  });
}
