import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';
import 'package:medintel_nexus/features/care_circle/application/care_circle_controller.dart';
import 'package:medintel_nexus/features/care_circle/domain/care_circle_models.dart';
import 'package:medintel_nexus/features/dashboard/application/dashboard_controller.dart';
import 'package:medintel_nexus/features/dashboard/presentation/home_dashboard_screen.dart';
import 'package:medintel_nexus/features/reminders/adherence_controller.dart';
import 'package:medintel_nexus/features/reminders/reminders_controller.dart';
import 'package:medintel_nexus/l10n/generated/app_localizations.dart';

class _FakeAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
        status: AuthStatus.authenticated,
        user: AuthUser(
          id: 'u1',
          role: UserRole.patient,
          onboardingComplete: true,
          fullName: 'Test User',
        ),
      );
}

class _FakeRemindersController extends RemindersController {
  @override
  MedicineManagerState build() => const MedicineManagerState();
}

class _FakeCareCircleController extends CareCircleController {
  _FakeCareCircleController(this.seed);
  final CareCircleState seed;

  @override
  CareCircleState build() => seed;
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required DashboardViewMode initialMode,
  required List<LinkedPatientView> linkedPatients,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        remindersControllerProvider.overrideWith(_FakeRemindersController.new),
        careCircleControllerProvider.overrideWith(
          () => _FakeCareCircleController(
            CareCircleState(linkedPatients: linkedPatients),
          ),
        ),
        dashboardStateProvider.overrideWithValue(
          const DashboardState(
            scansCount: 0,
            reportsCount: 0,
            medicineCount: 0,
            riskAlertCount: 0,
            recentScans: [],
            recentReports: [],
            insights: [],
            signals: [],
          ),
        ),
        dashboardViewModeProvider.overrideWith((ref) => initialMode),
      ],
      // ignore: prefer_const_constructors
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeDashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final linkedPatient = LinkedPatientView(
    member: CareCircleMember(
      id: 'm1',
      patientId: 'p1',
      patientDisplayName: 'Grandma Rosa',
      caregiverId: 'u1',
      caregiverDisplayName: 'Test User',
      status: 'active',
      createdAt: DateTime(2024, 1, 1),
    ),
    adherence: AdherenceState.empty,
  );

  testWidgets('mode toggle is always visible, even with no one linked yet',
      (tester) async {
    await _pumpDashboard(
      tester,
      initialMode: DashboardViewMode.me,
      linkedPatients: const [],
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Adherence'), findsOneWidget);
  });

  testWidgets('caregiver mode with no linked patients shows the empty-state CTA',
      (tester) async {
    await _pumpDashboard(
      tester,
      initialMode: DashboardViewMode.caregiver,
      linkedPatients: const [],
    );

    expect(find.text("You're not caring for anyone yet."), findsOneWidget);
    expect(find.text('Manage Care Circle'), findsOneWidget);
    expect(find.text('Adherence'), findsNothing);
  });

  testWidgets('caregiver mode shows the linked patient, not the patient dashboard',
      (tester) async {
    await _pumpDashboard(
      tester,
      initialMode: DashboardViewMode.caregiver,
      linkedPatients: [linkedPatient],
    );

    expect(find.text('Caring for'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Grandma Rosa'), findsOneWidget);
    expect(find.text('Manage Care Circle'), findsOneWidget);
    expect(find.text('Adherence'), findsNothing);
    expect(find.text('Quick actions'), findsNothing);
  });

  testWidgets('tapping the toggle switches from me to caregiver view', (tester) async {
    await _pumpDashboard(
      tester,
      initialMode: DashboardViewMode.me,
      linkedPatients: [linkedPatient],
    );

    expect(find.text('Adherence'), findsOneWidget);
    expect(find.text('Grandma Rosa'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Grandma Rosa'), findsOneWidget);
    expect(find.text('Adherence'), findsNothing);
  });
}
