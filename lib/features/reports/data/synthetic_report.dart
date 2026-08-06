import 'dart:math' as math;

import '../domain/medical_report.dart';

/// Generates a distinct, deterministic lab report for any uploaded file that
/// isn't the curated demo report. Same file (same seed) → identical output
/// every time; different files → different values, flags, summary & insights.
///
/// This is NOT real OCR — it produces plausible, varied results so different
/// uploads clearly differ during a demo, without a backend.
abstract final class SyntheticReport {
  /// A lab-panel template: label, unit, reference range, and the typical
  /// spread a generated value is drawn from.
  static const _panel = <_Spec>[
    _Spec('Total Cholesterol', 'mg/dL', 0, 200, 150, 240),
    _Spec('Triglycerides', 'mg/dL', 0, 150, 80, 220),
    _Spec('HDL Cholesterol', 'mg/dL', 40, 1e12, 30, 65),
    _Spec('LDL Cholesterol', 'mg/dL', 0, 100, 70, 165),
    _Spec('Uric Acid', 'mg/dL', 2.4, 5.7, 3.0, 8.2),
    _Spec('Haemoglobin', 'gm/dL', 12.0, 15.0, 10.5, 16.0),
    _Spec('WBC Count', 'cells/cu.mm', 4000, 11000, 4200, 12500),
    _Spec('Platelet Count', '10^3/uL', 150, 450, 130, 470),
    _Spec('Fasting Glucose', 'mg/dL', 70, 100, 78, 145),
    _Spec('HbA1c', '%', 4.0, 5.7, 4.8, 7.8),
    _Spec('TSH', 'uIU/mL', 0.54, 5.3, 0.4, 8.9),
    _Spec('Vitamin D', 'ng/mL', 30, 100, 12, 55),
  ];

  static MedicalReport build({
    required String id,
    required String seed,
    String? fileRef,
    DateTime? uploadedAt,
  }) {
    final rng = _Lcg(_hash(seed));

    // Pick 7–9 of the panel tests for this report.
    final count = 7 + rng.nextInt(3);
    final chosen = [..._panel]..shuffle(rng);
    final picks = chosen.take(count).toList();

    final metrics = <ReportMetric>[];
    for (final s in picks) {
      // Draw a value in the spread, rounded sensibly.
      final raw = s.spreadMin + rng.nextDouble() * (s.spreadMax - s.spreadMin);
      final value = s.spreadMax >= 1000
          ? raw.roundToDouble()
          : double.parse(raw.toStringAsFixed(raw >= 100 ? 0 : 1));
      metrics.add(
        ReportMetric(
          label: s.label,
          value: value,
          unit: s.unit,
          refLow: s.refLow,
          refHigh: s.refHigh,
        ),
      );
    }

    final flagged = metrics.where((m) => m.isOutOfRange).toList();

    final findings = <ReportFinding>[
      for (final m in flagged)
        ReportFinding(
          severity: 'caution',
          text: '${m.label} is ${m.value > m.refHigh ? 'high' : 'low'} at '
              '${_fmt(m.value)} ${m.unit} — outside the reference range.',
        ),
      if (flagged.isEmpty)
        const ReportFinding(
          severity: 'info',
          text: 'All measured values are within their reference ranges. No '
              'abnormal findings detected.',
        ),
    ];

    final summary = flagged.isEmpty
        ? 'Automated analysis of this lab panel found all '
            '${metrics.length} measured values within normal limits. No '
            'immediate concerns were flagged; continue routine monitoring.'
        : 'Automated analysis of this lab panel flagged ${flagged.length} of '
            '${metrics.length} values for review: '
            '${flagged.map((m) => '${m.label} (${_fmt(m.value)} ${m.unit})').join(', ')}. '
            'The remaining values are within normal limits.';

    final insights = <String>[
      if (flagged.isNotEmpty)
        'Share this report with your doctor to review the '
            '${flagged.length} flagged value${flagged.length == 1 ? '' : 's'}.'
      else
        'Your results look reassuring — keep up your routine check-ups.',
      'A balanced diet, regular activity, good hydration and adequate sleep '
          'support healthy lab values.',
      'This is an automated, informational analysis — confirm all findings '
          'and next steps with your physician.',
    ];

    return MedicalReport(
      id: id,
      type: ReportType.lab,
      title: _titleFromFile(fileRef, uploadedAt),
      uploadedAt: uploadedAt ?? DateTime.now(),
      status: ReportStatus.analyzed,
      fileRef: fileRef,
      isDemoMatched: true,
      ocrConfidence: 0.9,
      summary: summary,
      metrics: metrics,
      findings: findings,
      hasRiskFinding: flagged.isNotEmpty,
      insights: insights,
    );
  }

  static String _titleFromFile(String? fileRef, DateTime? at) {
    final d = at ?? DateTime.now();
    final date = '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.year}';
    return 'Lab Panel · $date';
  }

  static String _fmt(double v) {
    final r = v.roundToDouble();
    return v == r ? r.toStringAsFixed(0) : v.toString();
  }

  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }
}

class _Spec {
  const _Spec(
    this.label,
    this.unit,
    this.refLow,
    this.refHigh,
    this.spreadMin,
    this.spreadMax,
  );
  final String label;
  final String unit;
  final double refLow;
  final double refHigh;
  final double spreadMin;
  final double spreadMax;
}

/// Tiny deterministic PRNG (linear congruential), seeded so the same file
/// always yields the same report. Implements [math.Random] so it can be
/// passed to [List.shuffle].
class _Lcg implements math.Random {
  _Lcg(this._state);
  int _state;

  int _next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state;
  }

  @override
  int nextInt(int max) => _next() % max;

  @override
  double nextDouble() => _next() / 0x7fffffff;

  @override
  bool nextBool() => _next() & 1 == 0;
}
