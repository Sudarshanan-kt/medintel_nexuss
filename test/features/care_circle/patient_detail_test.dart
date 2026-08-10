import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';
import 'package:medintel_nexus/features/care_circle/application/care_circle_controller.dart';
import 'package:medintel_nexus/features/care_circle/application/care_task_controller.dart';
import 'package:medintel_nexus/features/care_circle/domain/care_circle_models.dart';
import 'package:medintel_nexus/features/care_circle/presentation/patient_detail_screen.dart';
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

CareCircleMember _member() => CareCircleMember(
      id: 'm1',
      patientId: 'p1',
      patientDisplayName: 'Grandma Rosa',
      caregiverId: 'c1',
      caregiverDisplayName: 'Asha Menon',
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    );

DoseLog _dose({
  required String id,
  required String name,
  required String status,
  required DateTime at,
  String slot = 'morning',
  String dosage = '500mg',
}) =>
    DoseLog(
      id: id,
      medicineId: 'med_$name',
      medicineName: name,
      dosage: dosage,
      scheduleSlot: slot,
      timestamp: at,
      status: status,
    );

Medicine _medicine(String name) => Medicine(
      id: 'med_$name',
      name: name,
      dosage: '500mg',
      frequency: 'Daily',
      morning: true,
      morningHour: 8,
      morningMinute: 0,
      afternoon: false,
      afternoonHour: 13,
      afternoonMinute: 0,
      night: true,
      nightHour: 21,
      nightMinute: 0,
      startDate: DateTime(2024, 1, 1),
      purpose: '',
      isCompleted: false,
      sound: 'default',
      repeatType: 'daily',
      createdAt: DateTime(2024, 1, 1),
    );

Future<void> _pump(WidgetTester tester, CareCircleState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        careCircleControllerProvider
            .overrideWith(() => _FakeCareCircleController(state)),
        careTasksProvider.overrideWith((ref, arg) async => <CareTask>[]),
      ],
      child: const MaterialApp(home: PatientDetailScreen(patientId: 'p1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final today = DateTime.now();

  testWidgets('names which medicine was missed and when', (tester) async {
    final logs = [
      _dose(
        id: 'd1',
        name: 'Amlodipine',
        status: 'missed',
        at: today,
        slot: 'night',
        dosage: '5mg',
      ),
      _dose(id: 'd2', name: 'Metformin', status: 'taken', at: today),
    ];

    await _pump(
      tester,
      CareCircleState(
        linkedPatients: [
          LinkedPatientView(
            member: _member(),
            adherence: computeAdherenceState(logs),
            logs: logs,
          ),
        ],
      ),
    );

    // The whole reason this screen exists: the dashboard could only say
    // "50%", never which drug or which dose.
    expect(find.text('Amlodipine · 5mg'), findsOneWidget);
    expect(find.text('this evening'), findsOneWidget);
    expect(find.text('Missed doses (1)'), findsOneWidget);
  });

  testWidgets('says so plainly when nothing has been missed', (tester) async {
    final logs = [
      _dose(id: 'd1', name: 'Metformin', status: 'taken', at: today),
    ];

    await _pump(
      tester,
      CareCircleState(
        linkedPatients: [
          LinkedPatientView(
            member: _member(),
            adherence: computeAdherenceState(logs),
            logs: logs,
          ),
        ],
      ),
    );

    expect(find.textContaining('Every dose recorded so far was taken'),
        findsOneWidget,);
  });

  testWidgets('lists the current regimen and states what is not shared',
      (tester) async {
    await _pump(
      tester,
      CareCircleState(
        linkedPatients: [
          LinkedPatientView(
            member: _member(),
            adherence: AdherenceState.empty,
            medicines: [_medicine('Metformin')],
          ),
        ],
      ),
    );

    expect(find.text('Metformin · 500mg'), findsOneWidget);
    expect(find.text('morning, evening'), findsOneWidget);
    // A caregiver reading a drug list must know it isn't the whole profile.
    expect(
      find.textContaining('not the rest of their health profile'),
      findsOneWidget,
    );
  });

  testWidgets('each day of the week chart carries a spoken description',
      (tester) async {
    final logs = [
      _dose(id: 'd1', name: 'Metformin', status: 'taken', at: today),
      _dose(id: 'd2', name: 'Amlodipine', status: 'missed', at: today),
    ];

    await _pump(
      tester,
      CareCircleState(
        linkedPatients: [
          LinkedPatientView(
            member: _member(),
            adherence: computeAdherenceState(logs),
            logs: logs,
          ),
        ],
      ),
    );

    // Colour alone can't convey this; the semantics tree has to.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp(r'1 missed, 1 taken')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'nothing logged')), findsWidgets);
    handle.dispose();
  });

  testWidgets('a revoked link stops showing health data', (tester) async {
    // The caregiver was removed while this screen was open, so the patient
    // is gone from the list. Showing the last-known numbers would be
    // showing data the patient has withdrawn.
    await _pump(tester, const CareCircleState(linkedPatients: []));

    expect(find.text("You're no longer linked to this person"), findsOneWidget);
    expect(find.text('Missed doses'), findsNothing);
  });
}
