import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/auth/application/auth_controller.dart';
import 'package:medintel_nexus/features/auth/domain/auth_user.dart';
import 'package:medintel_nexus/features/care_circle/data/care_task_repository.dart';
import 'package:medintel_nexus/features/care_circle/domain/care_circle_models.dart';
import 'package:medintel_nexus/features/care_circle/presentation/care_task_board.dart';

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

/// Records what the UI asked the server to do.
class _FakeTaskRepo implements CareTaskRepository {
  _FakeTaskRepo(this.tasks);

  List<CareTask> tasks;
  final List<String> calls = [];
  bool failNext = false;

  @override
  Future<List<CareTask>> listTasks(String patientId) async => tasks;

  @override
  Future<void> createTask({
    required String patientId,
    required String title,
    String? note,
    DateTime? dueDate,
    required String createdById,
    required String createdByName,
  }) async {
    if (failNext) throw Exception('nope');
    calls.add('create:$title:by=$createdById/$createdByName');
  }

  @override
  Future<void> claimTask({
    required String taskId,
    required String claimedById,
    required String claimedByName,
  }) async {
    if (failNext) throw Exception('nope');
    calls.add('claim:$taskId:by=$claimedById/$claimedByName');
  }

  @override
  Future<void> unclaimTask(String taskId) async => calls.add('unclaim:$taskId');

  @override
  Future<void> completeTask(String taskId) async {
    if (failNext) throw Exception('nope');
    calls.add('complete:$taskId');
  }

  @override
  Future<void> deleteTask(String taskId) async => calls.add('delete:$taskId');
}

CareTask _task({
  String id = 't1',
  String title = 'Ride to the clinic',
  String status = 'open',
  String? claimedById,
  String? claimedByName,
}) =>
    CareTask(
      id: id,
      patientId: 'p1',
      title: title,
      createdById: 'p1',
      createdByName: 'Rosa',
      claimedById: claimedById,
      claimedByName: claimedByName,
      status: status,
      createdAt: DateTime(2024, 1, 1),
    );

Future<_FakeTaskRepo> _pump(WidgetTester tester, List<CareTask> tasks) async {
  final repo = _FakeTaskRepo(tasks);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        careTaskRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CareTaskBoard(patientId: 'p1', patientName: 'Rosa'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  // Before this the board was read-only: it showed who had claimed what and
  // offered no way to claim or complete anything, even though the RLS
  // policies allowed any active member of the circle to do both.
  testWidgets('an unclaimed task can be claimed', (tester) async {
    final repo = await _pump(tester, [_task()]);

    expect(find.text('Ride to the clinic'), findsOneWidget);
    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['claim:t1:by=c1/Asha Menon']);
  });

  testWidgets('a task I claimed can be marked done', (tester) async {
    final repo = await _pump(tester, [
      _task(status: 'claimed', claimedById: 'c1', claimedByName: 'Asha Menon'),
    ]);

    expect(find.text("You're on it"), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['complete:t1']);
  });

  testWidgets("someone else's claim is shown but not actionable",
      (tester) async {
    await _pump(tester, [
      _task(status: 'claimed', claimedById: 'c2', claimedByName: 'Ravi'),
    ]);

    expect(find.text('Ravi is on it'), findsOneWidget);
    // Neither claiming it out from under them nor completing it for them.
    expect(find.text('Claim'), findsNothing);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('completed tasks drop off the board', (tester) async {
    await _pump(tester, [
      _task(id: 't1', title: 'Still open'),
      _task(id: 't2', title: 'Already handled', status: 'done'),
    ]);

    expect(find.text('Still open'), findsOneWidget);
    expect(find.text('Already handled'), findsNothing);
  });

  testWidgets('an empty board says so', (tester) async {
    await _pump(tester, []);
    expect(find.text('Nothing outstanding.'), findsOneWidget);
  });

  testWidgets('a failed claim tells the user instead of failing silently',
      (tester) async {
    final repo = await _pump(tester, [_task()]);
    repo.failNext = true;

    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.text("Couldn't claim that task."), findsOneWidget);
  });

  testWidgets('a task can be posted to the circle', (tester) async {
    final repo = await _pump(tester, []);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Everyone looking after Rosa'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'Collect her prescription',
    );
    await tester.tap(find.text('Post to the circle'));
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      ['create:Collect her prescription:by=c1/Asha Menon'],
    );
  });

  testWidgets('an empty title is refused', (tester) async {
    final repo = await _pump(tester, []);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post to the circle'));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.text('Give the task a title.'), findsOneWidget);
  });
}
