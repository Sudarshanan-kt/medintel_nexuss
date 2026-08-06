enum ReportType { lab, imaging, discharge, prescription }
enum ReportStatus { uploading, processing, analyzed, failed }

/// A lab/imaging/discharge report and its AI-derived intelligence layer.
class MedicalReport {
  const MedicalReport({
    required this.id,
    required this.type,
    required this.title,
    required this.uploadedAt,
    required this.status,
    this.fileRef,
    this.summary,
    this.metrics = const [],
    this.findings = const [],
    this.hasRiskFinding = false,
    this.medicines = const [],
    this.insights = const [],
    this.ocrConfidence,
    this.sha256,
    this.isDemoMatched = false,
  });

  final String id;
  final ReportType type;
  final String title;
  final DateTime uploadedAt;
  final ReportStatus status;

  /// Local path of the uploaded image/document.
  final String? fileRef;

  final String? summary;
  final List<ReportMetric> metrics;
  final List<ReportFinding> findings;
  final bool hasRiskFinding;

  /// Prescription medicines extracted by the OCR pipeline (or the demo OCR
  /// cache). Empty for non-prescription reports / when nothing was extracted.
  final List<PrescriptionMedicine> medicines;

  /// Plain-language insights produced from the analysis.
  final List<String> insights;

  /// Mean OCR confidence (0–1) when available.
  final double? ocrConfidence;

  /// SHA256 hex string of the uploaded image bytes.
  /// Used to look up and persist results in [RxLocalStore].
  final String? sha256;

  /// True when the result came from a demo/local cache match rather than
  /// the offline fallback — means medicines are prescription-specific.
  final bool isDemoMatched;

  MedicalReport copyWith({
    ReportStatus? status,
    String? title,
    String? summary,
    List<ReportMetric>? metrics,
    List<ReportFinding>? findings,
    bool? hasRiskFinding,
    List<PrescriptionMedicine>? medicines,
    List<String>? insights,
    double? ocrConfidence,
    String? sha256,
    bool? isDemoMatched,
  }) =>
      MedicalReport(
        id: id,
        type: type,
        title: title ?? this.title,
        uploadedAt: uploadedAt,
        status: status ?? this.status,
        fileRef: fileRef,
        summary: summary ?? this.summary,
        metrics: metrics ?? this.metrics,
        findings: findings ?? this.findings,
        hasRiskFinding: hasRiskFinding ?? this.hasRiskFinding,
        medicines: medicines ?? this.medicines,
        insights: insights ?? this.insights,
        ocrConfidence: ocrConfidence ?? this.ocrConfidence,
        sha256: sha256 ?? this.sha256,
        isDemoMatched: isDemoMatched ?? this.isDemoMatched,
      );

  String get typeLabel => switch (type) {
        ReportType.lab => 'Lab report',
        ReportType.imaging => 'Imaging',
        ReportType.discharge => 'Discharge summary',
        ReportType.prescription => 'Prescription',
      };

  // ── JSON (for local persistence across reloads) ────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'uploadedAt': uploadedAt.toIso8601String(),
        'status': status.name,
        'fileRef': fileRef,
        'summary': summary,
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'findings': findings.map((f) => f.toJson()).toList(),
        'hasRiskFinding': hasRiskFinding,
        'medicines': medicines.map((m) => m.toJson()).toList(),
        'insights': insights,
        'ocrConfidence': ocrConfidence,
        'sha256': sha256,
        'isDemoMatched': isDemoMatched,
      };

  static MedicalReport fromJson(Map<String, dynamic> j) => MedicalReport(
        id: (j['id'] as String?) ?? 'r_${DateTime.now().microsecondsSinceEpoch}',
        type: ReportType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => ReportType.lab,
        ),
        title: (j['title'] as String?) ?? 'Report',
        uploadedAt:
            DateTime.tryParse((j['uploadedAt'] as String?) ?? '') ??
                DateTime.now(),
        status: ReportStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => ReportStatus.analyzed,
        ),
        fileRef: j['fileRef'] as String?,
        summary: j['summary'] as String?,
        metrics: ((j['metrics'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ReportMetric.fromJson)
            .toList(),
        findings: ((j['findings'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ReportFinding.fromJson)
            .toList(),
        hasRiskFinding: (j['hasRiskFinding'] as bool?) ?? false,
        medicines: ((j['medicines'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PrescriptionMedicine.fromJson)
            .toList(),
        insights:
            ((j['insights'] as List?) ?? const []).map((e) => '$e').toList(),
        ocrConfidence: (j['ocrConfidence'] as num?)?.toDouble(),
        sha256: j['sha256'] as String?,
        isDemoMatched: (j['isDemoMatched'] as bool?) ?? false,
      );
}

class ReportMetric {
  const ReportMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.refLow,
    required this.refHigh,
  });

  final String label;
  final double value;
  final String unit;
  final double refLow;
  final double refHigh;

  bool get isOutOfRange => value < refLow || value > refHigh;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        'unit': unit,
        // JSON has no Infinity — store finite sentinels.
        'refLow': refLow.isFinite ? refLow : -1e12,
        'refHigh': refHigh.isFinite ? refHigh : 1e12,
      };

  static ReportMetric fromJson(Map<String, dynamic> e) => ReportMetric(
        label: (e['label'] as String?) ?? '',
        value: (e['value'] as num?)?.toDouble() ?? 0,
        unit: (e['unit'] as String?) ?? '',
        refLow: (e['refLow'] as num?)?.toDouble() ?? double.negativeInfinity,
        refHigh: (e['refHigh'] as num?)?.toDouble() ?? double.infinity,
      );
}

class ReportFinding {
  const ReportFinding({
    required this.severity,
    required this.text,
    this.explanation,
  });
  final String severity; // 'info' | 'caution' | 'severe'
  final String text;
  final String? explanation;

  Map<String, dynamic> toJson() => {
        'severity': severity,
        'text': text,
        'explanation': explanation,
      };

  static ReportFinding fromJson(Map<String, dynamic> j) => ReportFinding(
        severity: (j['severity'] as String?) ?? 'info',
        text: (j['text'] as String?) ?? '',
        explanation: j['explanation'] as String?,
      );
}

/// A medicine extracted from a prescription. `risk` is one of
/// 'none' | 'moderate' | 'severe' (kept as a plain string so the domain has
/// no dependency on the design-system RiskLevel enum).
class PrescriptionMedicine {
  const PrescriptionMedicine({
    required this.name,
    required this.strength,
    required this.dosageLine,
    this.risk = 'none',
    this.riskNote,
    this.confidence = 1.0,
  });

  final String name;
  final String strength;
  final String dosageLine;
  final String risk;
  final String? riskNote;
  final double confidence;

  bool get isLowConfidence => confidence < 0.7;

  Map<String, dynamic> toJson() => {
        'name': name,
        'strength': strength,
        'dosageLine': dosageLine,
        'risk': risk,
        'riskNote': riskNote,
        'confidence': confidence,
      };

  static PrescriptionMedicine fromJson(Map<String, dynamic> j) =>
      PrescriptionMedicine(
        name: (j['name'] as String?) ?? 'Medicine',
        strength: (j['strength'] as String?) ?? '',
        dosageLine: (j['dosageLine'] as String?) ?? '',
        risk: (j['risk'] as String?) ?? 'none',
        riskNote: j['riskNote'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
      );
}
