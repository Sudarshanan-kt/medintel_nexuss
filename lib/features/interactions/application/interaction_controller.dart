import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/interaction_repository.dart';
import '../domain/drug_interaction_result.dart';

/// Runs a fresh interaction check whenever [medicineNames] changes.
///
/// `.family` keyed on the exact list so re-selecting the same set of
/// medicines reuses the cached result instead of re-running the check.
final interactionCheckProvider = FutureProvider.autoDispose
    .family<InteractionCheck, List<String>>((ref, medicineNames) {
  return ref.watch(interactionRepositoryProvider).checkInteractions(
        medicineNames,
      );
});
