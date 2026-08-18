import 'medicine.dart';

enum ScanStatus { queued, processing, analyzed, failed }

/// A prescription scan and the medicines the patient has attached to it.
class PrescriptionScan {
  const PrescriptionScan({
    required this.id,
    required this.imageRef,
    required this.status,
    this.imageName,
    required this.medicines,
    this.capturedAt,
    this.note,
    this.serverId,
    this.ocrConfidence,
    this.errorMessage,
    this.verified = false,
    this.verifying = false,
  });

  final String id;

  /// How the capture is re-read: a filesystem path on mobile, a blob URL on
  /// web. Resolved through `MediaBytes`, never as a `File`.
  final String imageRef;

  /// The capturing picker's own name for the file, when it gave one.
  ///
  /// A blob URL carries no name or extension, so without this the backend
  /// would be told every web capture is a JPEG.
  final String? imageName;

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

  /// True once the extracted medicines are trusted — either the OCR read
  /// every drug name and strength confidently, or the patient confirmed the
  /// ones it wasn't sure about. Risk analysis does not run until then.
  final bool verified;

  /// True while the confirmation is in flight.
  final bool verifying;

  bool get hasRisk => medicines.any((m) => m.riskLevel.index > 0);

  /// True when the patient still has to confirm what was read.
  bool get needsReview =>
      status == ScanStatus.analyzed && medicines.isNotEmpty && !verified;

  /// Fields across all medicines the review UI should highlight.
  int get uncertainFieldCount =>
      medicines.fold(0, (sum, m) => sum + m.uncertainFields.length);

  PrescriptionScan copyWith({
    String? imageRef,
    String? imageName,
    ScanStatus? status,
    List<Medicine>? medicines,
    DateTime? capturedAt,
    String? note,
    String? serverId,
    double? ocrConfidence,
    String? errorMessage,
    bool clearError = false,
    bool? verified,
    bool? verifying,
  }) =>
      PrescriptionScan(
        id: id,
        imageRef: imageRef ?? this.imageRef,
        imageName: imageName ?? this.imageName,
        status: status ?? this.status,
        medicines: medicines ?? this.medicines,
        capturedAt: capturedAt ?? this.capturedAt,
        note: note ?? this.note,
        serverId: serverId ?? this.serverId,
        ocrConfidence: ocrConfidence ?? this.ocrConfidence,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        verified: verified ?? this.verified,
        verifying: verifying ?? this.verifying,
      );
}
