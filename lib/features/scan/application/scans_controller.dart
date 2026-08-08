import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/risk_badge.dart';
import '../data/scan_repository.dart';
import '../domain/medicine.dart';
import '../domain/prescription_scan.dart';

/// In-memory store of prescription scans the patient has captured.
///
/// Starts empty — nothing is shown until the user takes a real scan.
class ScansController extends Notifier<List<PrescriptionScan>> {
  @override
  List<PrescriptionScan> build() => const [];

  /// Called by the scanner after a photo is captured. Creates the scan in a
  /// [ScanStatus.processing] state and kicks off the OCR pipeline.
  PrescriptionScan addCapture(String imagePath) {
    final scan = PrescriptionScan(
      id: 's_${DateTime.now().microsecondsSinceEpoch}',
      imageRef: imagePath,
      status: ScanStatus.processing,
      medicines: const [],
      capturedAt: DateTime.now(),
    );
    state = [scan, ...state];
    // Fire-and-forget; the result screen watches state for progress.
    runOcr(scan.id);
    return scan;
  }

  /// Runs (or re-runs) the OCR pipeline for [scanId]: uploads the captured
  /// image, waits for the async worker, and folds the extracted medicines
  /// back into state. Safe to call again to retry a failed scan.
  Future<void> runOcr(String scanId) async {
    final scan = getById(scanId);
    if (scan == null) return;

    _patch(
      scanId,
      (s) => s.copyWith(status: ScanStatus.processing, clearError: true),
    );

    final result = await ref.read(scanRepositoryProvider).processPrescription(
          imagePath: scan.imageRef,
          capturedAt: scan.capturedAt,
          note: scan.note,
        );

    result.when(
      success: (outcome) => _patch(
        scanId,
        (s) => s.copyWith(
          status: ScanStatus.analyzed,
          serverId: outcome.prescriptionId,
          ocrConfidence: outcome.confidence,
          medicines: outcome.medicines,
          verified: outcome.verified,
          clearError: true,
        ),
      ),
      failure: (f) => _patch(
        scanId,
        (s) => s.copyWith(
          status: ScanStatus.failed,
          errorMessage: f.message,
        ),
      ),
    );
  }

  /// Submits the medicines as the patient has them now — corrections
  /// included — as their confirmation of what the prescription says. This is
  /// what releases the risk analysis the pipeline withheld, so on success
  /// the medicines come back carrying interaction risk levels.
  ///
  /// Returns an error message on failure, or null when it went through.
  Future<String?> confirmMedicines(String scanId) async {
    final scan = getById(scanId);
    if (scan == null) return null;
    if (scan.medicines.isEmpty) {
      return 'Add at least one medicine before confirming.';
    }
    if (scan.verifying) return null;

    _patch(scanId, (s) => s.copyWith(verifying: true, clearError: true));

    final result = await ref.read(scanRepositoryProvider).verifyMedicines(
          prescriptionId: scan.serverId ?? scan.id,
          medicines: scan.medicines,
        );

    String? error;
    result.when(
      success: (outcome) => _patch(
        scanId,
        (s) => s.copyWith(
          medicines: outcome.medicines,
          verified: outcome.verified,
          verifying: false,
          ocrConfidence: outcome.confidence ?? s.ocrConfidence,
        ),
      ),
      failure: (f) {
        error = f.message;
        _patch(scanId, (s) => s.copyWith(verifying: false));
      },
    );
    return error;
  }

  void _patch(
    String scanId,
    PrescriptionScan Function(PrescriptionScan) update,
  ) {
    state = [
      for (final s in state)
        if (s.id == scanId) update(s) else s,
    ];
  }

  PrescriptionScan? getById(String id) {
    for (final s in state) {
      if (s.id == id) return s;
    }
    return null;
  }

  // Any change to the medicine list makes an earlier confirmation stale —
  // the risk verdict was computed for a different set of drugs. Reopening
  // the gate forces it to be recomputed against what's actually there now.
  void addMedicine(String scanId, Medicine medicine) {
    _patch(
      scanId,
      (s) => s.copyWith(
        medicines: [...s.medicines, medicine.confirmed(corrected: true)],
        verified: false,
      ),
    );
  }

  void updateMedicine(String scanId, Medicine medicine) {
    _patch(
      scanId,
      (s) => s.copyWith(
        medicines: [
          for (final m in s.medicines)
            if (m.id == medicine.id) medicine else m,
        ],
        verified: false,
      ),
    );
  }

  void removeMedicine(String scanId, String medicineId) {
    _patch(
      scanId,
      (s) => s.copyWith(
        medicines: s.medicines.where((m) => m.id != medicineId).toList(),
        verified: false,
      ),
    );
  }

  void deleteScan(String id) {
    state = state.where((s) => s.id != id).toList();
  }

  /// Convenience: total number of distinct medicines across all scans.
  int get totalMedicineCount =>
      state.fold(0, (sum, s) => sum + s.medicines.length);

  int get riskAlertCount {
    var c = 0;
    for (final s in state) {
      for (final m in s.medicines) {
        if (m.riskLevel != RiskLevel.none) c++;
      }
    }
    return c;
  }
}

final scansControllerProvider =
    NotifierProvider<ScansController, List<PrescriptionScan>>(
  ScansController.new,
);
