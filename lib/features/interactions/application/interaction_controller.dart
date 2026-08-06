import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/interaction_repository.dart';
import '../domain/drug_interaction_result.dart';

/// Runs a fresh interaction check whenever [medicineNames] changes.
///
/// `.family` keyed on the exact list so re-selecting the same set of
/// medicines reuses the cached result instead of re-hitting the network.
final interactionCheckProvider = FutureProvider.autoDispose
    .family<List<DrugInteractionResult>, List<String>>((ref, medicineNames) {
  final repo = ref.watch(interactionRepositoryProvider);
  return repo.checkInteractions(medicineNames);
});
