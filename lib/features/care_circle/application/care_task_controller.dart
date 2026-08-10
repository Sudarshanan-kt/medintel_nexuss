import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_user.dart';
import '../data/care_task_repository.dart';
import '../domain/care_circle_models.dart';

/// Tasks for one circle, keyed by [patientId] — a patient only ever needs
/// their own, a caregiver needs one per linked patient, so this stays a
/// simple fetch-per-key rather than a combined cross-circle store.
final careTasksProvider =
    FutureProvider.autoDispose.family<List<CareTask>, String>((ref, patientId) {
  final repo = ref.watch(careTaskRepositoryProvider);
  return repo.listTasks(patientId);
});

/// Posting, claiming and completing tasks.
///
/// Split from [careTasksProvider] so the list stays a plain fetch: every
/// mutation here ends by invalidating that provider rather than patching a
/// local copy. Two people in a circle act on the same board at the same
/// time — a claim that only updated this device would show two caregivers
/// each believing they had it.
class CareTaskActions {
  const CareTaskActions(this._ref);
  final Ref _ref;

  CareTaskRepository get _repo => _ref.read(careTaskRepositoryProvider);

  /// Identity comes from the auth controller rather than
  /// `Supabase.instance` directly. Same answer, but it keeps the widget
  /// tree off a global singleton that throws when Supabase hasn't been
  /// initialised — [claimedByMe] runs during build.
  ///
  /// Awaited rather than read as a snapshot: [authControllerProvider] builds
  /// asynchronously, so a caller that happens to be the first to touch it
  /// sees `AsyncLoading` and a null user. Reporting that as "session
  /// expired" to someone who is perfectly well signed in is the kind of
  /// error that trains people to distrust the app.
  Future<AuthUser> _requireUser() async {
    final state = await _ref.read(authControllerProvider.future);
    final user = state.user;
    if (user == null) {
      throw Exception('Session expired. Please sign in again.');
    }
    return user;
  }

  Future<void> add({
    required String patientId,
    required String title,
    String? note,
    DateTime? dueDate,
  }) async {
    // Validated before the await so an empty title fails instantly and
    // without a network round trip.
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw Exception('Give the task a title.');

    final user = await _requireUser();

    await _repo.createTask(
      patientId: patientId,
      title: trimmed,
      note: (note ?? '').trim().isEmpty ? null : note!.trim(),
      dueDate: dueDate,
      createdById: user.id,
      createdByName: user.displayName,
    );
    _ref.invalidate(careTasksProvider(patientId));
  }

  Future<void> claim(CareTask task) async {
    final user = await _requireUser();

    await _repo.claimTask(
      taskId: task.id,
      claimedById: user.id,
      claimedByName: user.displayName,
    );
    _ref.invalidate(careTasksProvider(task.patientId));
  }

  Future<void> unclaim(CareTask task) async {
    await _repo.unclaimTask(task.id);
    _ref.invalidate(careTasksProvider(task.patientId));
  }

  Future<void> complete(CareTask task) async {
    await _repo.completeTask(task.id);
    _ref.invalidate(careTasksProvider(task.patientId));
  }

  /// True when the signed-in user is the one who claimed [task] — the only
  /// person offered "mark it done".
  ///
  /// Synchronous because it runs during build. While auth is still
  /// resolving this answers false, which hides the action rather than
  /// offering one that would fail; [CareTaskBoard] watches the auth
  /// provider so the row rebuilds the moment it settles.
  bool claimedByMe(CareTask task) {
    final id = _ref.read(authControllerProvider).valueOrNull?.user?.id;
    return id != null && task.claimedById == id;
  }
}

final careTaskActionsProvider = Provider<CareTaskActions>(CareTaskActions.new);
