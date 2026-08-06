import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scan/application/scans_controller.dart';
import '../../scan/domain/medicine.dart';
import '../../scan/domain/prescription_scan.dart';
import '../data/savings_service.dart';
import '../domain/generic_swap.dart';

class SavingsState {
  const SavingsState({
    this.swaps = const [],
    this.loading = false,
    this.checkedMedicineIds = const {},
  });

  final List<GenericSwap> swaps;
  final bool loading;

  /// Medicine ids already looked up this session — avoids re-querying the
  /// same medicine every time the scan list changes.
  final Set<String> checkedMedicineIds;

  /// Swaps worth surfacing to the user — real savings only.
  List<GenericSwap> get actionable =>
      swaps.where((s) => !s.isAlreadyGeneric).toList();

  SavingsState copyWith({
    List<GenericSwap>? swaps,
    bool? loading,
    Set<String>? checkedMedicineIds,
  }) =>
      SavingsState(
        swaps: swaps ?? this.swaps,
        loading: loading ?? this.loading,
        checkedMedicineIds: checkedMedicineIds ?? this.checkedMedicineIds,
      );
}

/// Watches the patient's scanned medicines and looks up a generic-swap
/// estimate for any medicine not already checked this session. Mirrors
/// WearablesController's "derive from another controller's state" shape.
class SavingsController extends Notifier<SavingsState> {
  SavingsService get _service => ref.read(savingsServiceProvider);

  @override
  SavingsState build() {
    ref.listen<List<PrescriptionScan>>(
      scansControllerProvider,
      (_, scans) => _checkNew(scans),
    );
    Future.microtask(() => _checkNew(ref.read(scansControllerProvider)));
    return const SavingsState();
  }

  Future<void> _checkNew(List<PrescriptionScan> scans) async {
    final seenNames = <String>{};
    final toCheck = <Medicine>[];
    for (final scan in scans) {
      for (final m in scan.medicines) {
        final key = m.name.trim().toLowerCase();
        if (key.isEmpty || !seenNames.add(key)) continue;
        if (state.checkedMedicineIds.contains(m.id)) continue;
        toCheck.add(m);
      }
    }
    if (toCheck.isEmpty) return;

    state = state.copyWith(loading: true);
    final results = await _service.findGenericSwaps(toCheck);
    state = state.copyWith(
      swaps: [...state.swaps, ...results],
      loading: false,
      checkedMedicineIds: {
        ...state.checkedMedicineIds,
        ...toCheck.map((m) => m.id),
      },
    );
  }

  /// Clears the session cache and re-checks every currently scanned medicine.
  Future<void> refresh() async {
    state = const SavingsState();
    await _checkNew(ref.read(scansControllerProvider));
  }
}

final savingsControllerProvider =
    NotifierProvider<SavingsController, SavingsState>(SavingsController.new);
