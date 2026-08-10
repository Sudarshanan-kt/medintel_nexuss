import 'medical_report.dart';

/// The analysed contents of one uploaded report.
///
/// Was `DemoOcrResult`, defined alongside a bundled cache of pre-extracted
/// answers for a handful of demo files. That cache is gone: an uploaded
/// report is now analysed for real or not at all. The type stays because it
/// was never actually demo-specific — it is the shape every analysis
/// produces, and [RxLocalStore] persists genuine results in it so a report
/// already analysed once isn't sent through OCR again.
class ReportAnalysis {
  const ReportAnalysis({
    required this.id,
    required this.title,
    required this.confidence,
    required this.summary,
    required this.medicines,
    required this.riskAnalysis,
    required this.insights,
    this.metrics = const [],
  });

  final String id;
  final String title;
  final double confidence;
  final String summary;
  final List<PrescriptionMedicine> medicines;
  final List<String> riskAnalysis;
  final List<String> insights;

  /// Structured lab values (name, value, unit, reference range) for lab/
  /// imaging reports. Empty for prescriptions.
  final List<ReportMetric> metrics;

  static List<ReportMetric> metricsFromJsonList(List<dynamic>? raw) => [
        for (final e in (raw ?? const []).cast<Map<String, dynamic>>())
          ReportMetric(
            label: (e['label'] as String?) ?? '',
            value: (e['value'] as num?)?.toDouble() ?? 0,
            unit: (e['unit'] as String?) ?? '',
            refLow: (e['refLow'] as num?)?.toDouble() ?? double.negativeInfinity,
            refHigh: (e['refHigh'] as num?)?.toDouble() ?? double.infinity,
          ),
      ];

  /// Maps the risk-analysis lines onto [ReportFinding]s for the viewer.
  List<ReportFinding> get findings => [
        for (final line in riskAnalysis)
          ReportFinding(
            severity: medicines.any((m) => m.risk == 'severe')
                ? 'severe'
                : (medicines.any((m) => m.risk == 'moderate')
                    ? 'caution'
                    // For lab reports (no medicines), flag caution when any
                    // measured value falls outside its reference range.
                    : (metrics.any((m) => m.isOutOfRange)
                        ? 'caution'
                        : 'info')),
            text: line,
          ),
      ];

  bool get hasRisk => medicines.any((m) => m.risk != 'none');
}
