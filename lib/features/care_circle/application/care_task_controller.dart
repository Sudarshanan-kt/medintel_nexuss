import 'package:flutter_riverpod/flutter_riverpod.dart';

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
