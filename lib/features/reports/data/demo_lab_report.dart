import '../domain/medical_report.dart';

/// Hard-coded, pre-extracted analysis for the presentation demo file
/// `Report-250000514125417_Mrs.TAMILARASIK_05Feb2026_062100.pdf`.
///
/// This is a guaranteed, synchronous path: NO OCR, NO DemoOcrCache asset load,
/// NO SharedPreferences, NO background Future. Building this report yields a
/// fully `analyzed` [MedicalReport] immediately so the viewer can render
/// Summary / Lab Findings / Risk Analysis / Insights right away.
class DemoLabReport {
  const DemoLabReport._();

  /// File-name fragment that triggers the guaranteed demo path.
  static const matchStem = 'tamilarasi';

  static bool matches(String? fileName) =>
      (fileName ?? '').toLowerCase().contains(matchStem);

  /// Builds the fully-analyzed report for the demo file.
  static MedicalReport build({
    required String id,
    String? fileRef,
    String? sha256,
    DateTime? uploadedAt,
  }) {
    return MedicalReport(
      id: id,
      type: ReportType.lab,
      title: 'Lab Panel · Lipid, CBC & Thyroid (05 Feb 2026)',
      uploadedAt: uploadedAt ?? DateTime.now(),
      status: ReportStatus.analyzed,
      fileRef: fileRef,
      sha256: sha256,
      isDemoMatched: true,
      ocrConfidence: 0.97,
      summary:
          'Fasting lipid profile, complete blood count with ESR, and thyroid '
          'panel for a 58-year-old woman. Most results are within normal '
          'limits. Two findings stand out and warrant a doctor’s review: '
          'the thyroid-stimulating hormone (TSH) is clearly raised at 9.34 '
          '(normal 0.54–5.3) while FT3 and FT4 are normal — a pattern '
          'consistent with subclinical hypothyroidism — and serum uric '
          'acid is high at 7.0 (normal 2.4–5.7). Cholesterol is well '
          'controlled overall, with LDL only mildly above the optimal target.',
      hasRiskFinding: true,
      metrics: const [
        ReportMetric(label: 'Total Cholesterol', value: 187, unit: 'mg/dL', refLow: 0, refHigh: 200),
        ReportMetric(label: 'Triglycerides', value: 132, unit: 'mg/dL', refLow: 0, refHigh: 150),
        ReportMetric(label: 'HDL Cholesterol', value: 41.4, unit: 'mg/dL', refLow: 40, refHigh: double.infinity),
        ReportMetric(label: 'LDL Cholesterol', value: 119, unit: 'mg/dL', refLow: 0, refHigh: 100),
        ReportMetric(label: 'Non-HDL Cholesterol', value: 145.6, unit: 'mg/dL', refLow: 0, refHigh: 130),
        ReportMetric(label: 'Uric Acid', value: 7.0, unit: 'mg/dL', refLow: 2.4, refHigh: 5.7),
        ReportMetric(label: 'Haemoglobin', value: 13.4, unit: 'gm/dL', refLow: 12.0, refHigh: 15.0),
        ReportMetric(label: 'WBC Count', value: 6230, unit: 'cells/cu.mm', refLow: 4000, refHigh: 11000),
        ReportMetric(label: 'MCHC', value: 30.9, unit: 'gm/dL', refLow: 31.5, refHigh: 34.5),
        ReportMetric(label: 'Platelet Count', value: 291, unit: '10^3/uL', refLow: 150, refHigh: 450),
        ReportMetric(label: 'ESR', value: 18, unit: 'mm/hr', refLow: 5, refHigh: 20),
        ReportMetric(label: 'FT3', value: 2.41, unit: 'pg/mL', refLow: 2.0, refHigh: 4.4),
        ReportMetric(label: 'FT4', value: 1.15, unit: 'ng/dL', refLow: 0.93, refHigh: 1.7),
        ReportMetric(label: 'TSH', value: 9.34, unit: 'uIU/mL', refLow: 0.54, refHigh: 5.3),
      ],
      findings: const [
        ReportFinding(
          severity: 'caution',
          text:
              'TSH high at 9.34 µIU/mL (ref 0.54–5.3) with normal FT3 '
              '(2.41) and FT4 (1.15) — pattern of subclinical '
              'hypothyroidism; an underactive thyroid that may need monitoring '
              'or treatment.',
        ),
        ReportFinding(
          severity: 'caution',
          text:
              'Uric Acid high at 7.0 mg/dL (ref 2.4–5.7) — '
              'hyperuricemia, which raises the risk of gout and kidney stones.',
        ),
        ReportFinding(
          severity: 'info',
          text:
              'LDL Cholesterol 119 mg/dL (optimal <100) and Non-HDL 145.6 '
              'mg/dL (optimal <130) are mildly above optimal targets.',
        ),
        ReportFinding(
          severity: 'info',
          text:
              'MCHC slightly low at 30.9 gm/dL (ref 31.5–34.5) and '
              'absolute monocytes slightly low at 187 cells/cu.mm (ref '
              '200–1000) — minor, generally not significant in '
              'isolation.',
        ),
        ReportFinding(
          severity: 'info',
          text:
              'ESR is at the upper end of normal (18 mm/hr, ref 5–20); '
              'blood count is otherwise unremarkable with normal haemoglobin '
              'and platelets.',
        ),
      ],
      insights: const [
        'Share this report with your doctor — the raised TSH most likely '
            'needs a repeat thyroid test and a clinical review to decide if '
            'treatment is required.',
        'The high uric acid can often be helped by staying well hydrated and '
            'reducing red meat, organ meats, shellfish, alcohol and sugary '
            'drinks; your doctor may check kidney function.',
        'Lipids are largely well controlled; keeping up a heart-healthy diet '
            'and regular activity should help bring LDL fully into the optimal '
            'range.',
        'Overall blood count is reassuring — normal haemoglobin, white '
            'cells and platelets, with no sign of anaemia or infection.',
        'This is informational only and not a diagnosis; please confirm all '
            'findings and next steps with your physician.',
      ],
    );
  }
}
