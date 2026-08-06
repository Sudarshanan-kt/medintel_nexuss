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

  void addMedicine(String scanId, Medicine medicine) {
    state = [
      for (final s in state)
        if (s.id == scanId)
          s.copyWith(medicines: [...s.medicines, medicine])
        else
          s,
    ];
  }

  void updateMedicine(String scanId, Medicine medicine) {
    state = [
      for (final s in state)
        if (s.id == scanId)
          s.copyWith(
            medicines: [
              for (final m in s.medicines)
                if (m.id == medicine.id) medicine else m,
            ],
          )
        else
          s,
    ];
  }

  void removeMedicine(String scanId, String medicineId) {
    state = [
      for (final s in state)
        if (s.id == scanId)
          s.copyWith(
            medicines:
                s.medicines.where((m) => m.id != medicineId).toList(),
          )
        else
          s,
    ];
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
