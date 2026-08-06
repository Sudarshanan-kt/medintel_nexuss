import 'medicine.dart';

enum ScanStatus { queued, processing, analyzed, failed }

/// A prescription scan and the medicines the patient has attached to it.
class PrescriptionScan {
  const PrescriptionScan({
    required this.id,
    required this.imageRef,
    required this.status,
    required this.medicines,
    this.capturedAt,
    this.note,
    this.serverId,
    this.ocrConfidence,
    this.errorMessage,
  });

  final String id;
  final String imageRef;
  final ScanStatus status;
  final List<Medicine> medicines;
  final DateTime? capturedAt;
  final String? note;

  /// Backend prescription id once the OCR pipeline has registered the scan.
  final String? serverId;

  /// Mean OCR confidence reported by the pipeline (0–1).
  final double? ocrConfidence;

  /// Set when [status] is [ScanStatus.failed]; user-facing reason.
  final String? errorMessage;

  bool get hasRisk => medicines.any((m) => m.riskLevel.index > 0);

  PrescriptionScan copyWith({
    String? imageRef,
    ScanStatus? status,
    List<Medicine>? medicines,
    DateTime? capturedAt,
    String? note,
    String? serverId,
    double? ocrConfidence,
    String? errorMessage,
    bool clearError = false,
  }) =>
      PrescriptionScan(
        id: id,
        imageRef: imageRef ?? this.imageRef,
        status: status ?? this.status,
        medicines: medicines ?? this.medicines,
        capturedAt: capturedAt ?? this.capturedAt,
        note: note ?? this.note,
        serverId: serverId ?? this.serverId,
        ocrConfidence: ocrConfidence ?? this.ocrConfidence,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}
