/// Reference knowledge about lab analytes: which panel a value belongs to,
/// how far outside its range it actually is, and what it measures in plain
/// English.
///
/// Plain Dart on purpose — this is domain knowledge, not presentation, and
/// the viewer, the trend screen and any future export all need the same
/// answers. Nothing here talks to the model or the backend: a report that
/// arrives while the model is down still groups, grades and explains.
///
/// Everything is keyed off the analyte *label* as OCR read it, which is
/// messy by nature ("S. Creatinine", "CREATININE (serum)", "Creatinine -
/// Serum"). [_normalise] and the alias lists absorb that; an unrecognised
/// label falls back to [MetricPanel.other] with no glossary entry rather
/// than guessing, because a wrong explanation on a medical value is worse
/// than none.
library;

import 'medical_report.dart';

/// The panels a report is grouped into, in the order a lab prints them.
enum MetricPanel {
  haematology('Blood count'),
  diabetes('Diabetes'),
  lipid('Lipid profile'),
  liver('Liver function'),
  kidney('Kidney function'),
  thyroid('Thyroid'),
  electrolyte('Electrolytes'),
  vitamin('Vitamins & iron'),
  inflammation('Inflammation'),
  other('Other results');

  const MetricPanel(this.label);

  /// Human-readable heading for this panel.
  final String label;
}

/// How far outside its reference range a value sits.
///
/// A flat in-or-out flag treats a hair over the line the same as a value
/// that belongs in an emergency room. These are the four steps a report
/// reader actually acts on.
enum MetricSeverity {
  normal,
  mild,
  moderate,
  critical;

  bool get isOutOfRange => this != MetricSeverity.normal;
}

/// A graded reading: which way it deviates and by how much.
class MetricGrade {
  const MetricGrade({
    required this.severity,
    required this.isHigh,
  });

  final MetricSeverity severity;

  /// True when the value is above the range, false when below. Meaningless
  /// for [MetricSeverity.normal].
  final bool isHigh;

  /// "High" / "Critically low" / "" — the badge text for this reading.
  String get label {
    final direction = isHigh ? 'high' : 'low';
    switch (severity) {
      case MetricSeverity.normal:
        return '';
      case MetricSeverity.mild:
        return 'Slightly $direction';
      case MetricSeverity.moderate:
        return direction == 'high' ? 'High' : 'Low';
      case MetricSeverity.critical:
        return 'Critically $direction';
    }
  }
}

/// What an analyte measures, and what a value outside its range suggests.
class MetricExplainer {
  const MetricExplainer({
    required this.what,
    required this.high,
    required this.low,
  });

  /// One sentence: what this value measures.
  final String what;

  /// What a high reading commonly points to.
  final String high;

  /// What a low reading commonly points to.
  final String low;
}

/// Which panel [label] belongs to.
MetricPanel panelFor(String label) {
  final key = _normalise(label);
  for (final entry in _panels.entries) {
    for (final alias in entry.value) {
      if (key.contains(alias)) return entry.key;
    }
  }
  return MetricPanel.other;
}

/// Grades [metric] against its own reference range, and against fixed
/// critical thresholds where one is known for that analyte.
///
/// Two independent judgements, and the worse one wins. The relative test
/// ("how far past the line, as a fraction of the range's own width") is
/// what generalises across analytes nobody has written a threshold for. The
/// fixed thresholds exist because relative distance is the wrong measure for
/// the values that kill people: a potassium of 6.6 is a medical emergency
/// while sitting only ~30% past a 3.5–5.1 range, which the relative test
/// alone would call moderate.
MetricGrade gradeFor(ReportMetric metric) {
  final isHigh = metric.value > metric.refHigh;
  if (!metric.isOutOfRange) {
    return const MetricGrade(
      severity: MetricSeverity.normal,
      isHigh: false,
    );
  }

  return MetricGrade(
    severity: _worse(
      _relativeSeverity(metric, isHigh: isHigh),
      _criticalThresholdSeverity(metric, isHigh: isHigh),
    ),
    isHigh: isHigh,
  );
}

/// The plain-language explainer for [label], or null if this analyte is not
/// one we can describe accurately.
MetricExplainer? explainerFor(String label) {
  final key = _normalise(label);
  for (final entry in _explainers.entries) {
    for (final alias in entry.key) {
      if (key.contains(alias)) return entry.value;
    }
  }
  return null;
}

/// Groups [metrics] into panels, keeping panel order and dropping empties.
Map<MetricPanel, List<ReportMetric>> groupByPanel(List<ReportMetric> metrics) {
  final grouped = <MetricPanel, List<ReportMetric>>{};
  for (final metric in metrics) {
    grouped.putIfAbsent(panelFor(metric.label), () => []).add(metric);
  }
  return {
    for (final panel in MetricPanel.values)
      if (grouped[panel] != null) panel: grouped[panel]!,
  };
}

/// The worst grade across [metrics] — what the report as a whole warrants.
MetricSeverity worstSeverity(List<ReportMetric> metrics) {
  var worst = MetricSeverity.normal;
  for (final metric in metrics) {
    worst = _worse(worst, gradeFor(metric).severity);
  }
  return worst;
}

// ── internals ───────────────────────────────────────────────────────────────

MetricSeverity _worse(MetricSeverity a, MetricSeverity b) =>
    a.index >= b.index ? a : b;

/// Distance past the range, measured in units of the range's own width.
///
/// Falling back to the bound itself when only one side is finite ("< 200")
/// keeps a one-sided range from being ungradeable: 260 against "< 200" is
/// 30% over, which reads the same way a two-sided range would.
MetricSeverity _relativeSeverity(ReportMetric m, {required bool isHigh}) {
  final low = m.refLow.isFinite && m.refLow > -1e11 ? m.refLow : null;
  final high = m.refHigh.isFinite && m.refHigh < 1e11 ? m.refHigh : null;

  double? span;
  if (low != null && high != null && high > low) {
    span = high - low;
  } else if (isHigh && high != null && high > 0) {
    span = high;
  } else if (!isHigh && low != null && low > 0) {
    span = low;
  }
  if (span == null || span <= 0) return MetricSeverity.mild;

  final excess = isHigh ? m.value - (high ?? 0) : (low ?? 0) - m.value;
  final ratio = excess / span;
  if (ratio <= 0.15) return MetricSeverity.mild;
  if (ratio <= 0.6) return MetricSeverity.moderate;
  return MetricSeverity.critical;
}

/// Fixed thresholds for analytes where a specific number, not a distance,
/// is what makes a result urgent. Values are the common adult panic limits
/// used by hospital labs; units are the ones these analytes are normally
/// reported in here, and a reading in some other unit simply fails the
/// comparison rather than mis-grading it.
MetricSeverity _criticalThresholdSeverity(
  ReportMetric m, {
  required bool isHigh,
}) {
  final key = _normalise(m.label);
  for (final entry in _criticalLimits.entries) {
    if (!entry.key.any(key.contains)) continue;
    final limits = entry.value;
    if (isHigh && limits.high != null && m.value >= limits.high!) {
      return MetricSeverity.critical;
    }
    if (!isHigh && limits.low != null && m.value <= limits.low!) {
      return MetricSeverity.critical;
    }
  }
  return MetricSeverity.mild;
}

class _CriticalLimits {
  const _CriticalLimits({this.low, this.high});
  final double? low;
  final double? high;
}

/// Lowercase, letters and digits only, so "S. Creatinine (serum)" and
/// "CREATININE-SERUM" collapse to the same key.
String _normalise(String label) =>
    label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const Map<MetricPanel, List<String>> _panels = {
  MetricPanel.diabetes: ['hba1c', 'glycated', 'glucose', 'sugar', 'insulin'],
  MetricPanel.lipid: [
    'cholesterol',
    'ldl',
    'hdl',
    'vldl',
    'triglyceride',
    'lipid',
  ],
  MetricPanel.thyroid: ['tsh', 'thyroid', 't3', 't4', 'thyroxine'],
  MetricPanel.liver: [
    'bilirubin',
    'sgpt',
    'sgot',
    'alt',
    'ast',
    'alkalinephosphatase',
    'alp',
    'albumin',
    'globulin',
    'totalprotein',
    'ggt',
  ],
  MetricPanel.kidney: [
    'creatinine',
    'urea',
    'bun',
    'uricacid',
    'egfr',
    'microalbumin',
  ],
  MetricPanel.electrolyte: [
    'sodium',
    'potassium',
    'chloride',
    'calcium',
    'magnesium',
    'phosphorus',
    'bicarbonate',
  ],
  MetricPanel.haematology: [
    'haemoglobin',
    'hemoglobin',
    'hb',
    'hct',
    'haematocrit',
    'hematocrit',
    'rbc',
    'wbc',
    'leucocyte',
    'leukocyte',
    'platelet',
    'mcv',
    'mch',
    'mchc',
    'rdw',
    'neutrophil',
    'lymphocyte',
    'monocyte',
    'eosinophil',
    'basophil',
  ],
  MetricPanel.vitamin: [
    'vitamin',
    'b12',
    'folate',
    'ferritin',
    'iron',
    'tibc',
  ],
  MetricPanel.inflammation: ['crp', 'esr', 'procalcitonin'],
};

/// Adult critical (panic) limits, in the units these are normally reported
/// in: mg/dL for glucose and creatinine, mEq/L for electrolytes, g/dL for
/// haemoglobin, cells or lakhs as printed for counts.
const Map<List<String>, _CriticalLimits> _criticalLimits = {
  ['potassium']: _CriticalLimits(low: 2.8, high: 6.2),
  ['sodium']: _CriticalLimits(low: 120, high: 158),
  ['glucose', 'sugar']: _CriticalLimits(low: 50, high: 400),
  ['calcium']: _CriticalLimits(low: 6.5, high: 13),
  ['haemoglobin', 'hemoglobin']: _CriticalLimits(low: 7, high: 20),
  ['creatinine']: _CriticalLimits(high: 4),
  ['bilirubin']: _CriticalLimits(high: 15),
  ['hba1c']: _CriticalLimits(high: 10),
};

const Map<List<String>, MetricExplainer> _explainers = {
  ['haemoglobin', 'hemoglobin']: MetricExplainer(
    what: 'The protein in red blood cells that carries oxygen around your '
        'body.',
    high: 'Often dehydration, smoking, or living at altitude; occasionally '
        'the marrow making too many red cells.',
    low: 'Anaemia — commonly low iron, blood loss, or a long-term illness. '
        'It is what makes people feel tired and short of breath.',
  ),
  ['platelet']: MetricExplainer(
    what: 'The cell fragments that clump together to stop bleeding.',
    high: 'Can follow infection or inflammation, and occasionally a marrow '
        'condition.',
    low: 'Raises bruising and bleeding risk; seen in dengue, some '
        'infections, and reactions to medicines.',
  ),
  ['wbc', 'leucocyte', 'leukocyte']: MetricExplainer(
    what: 'Your white blood cells — the immune system\'s response force.',
    high: 'Usually an infection or inflammation somewhere; also stress and '
        'steroids.',
    low: 'Reduced ability to fight infection; viral illness and some '
        'medicines lower it.',
  ),
  ['hba1c', 'glycated']: MetricExplainer(
    what: 'Your average blood sugar over roughly the last three months, so '
        'one bad day does not move it.',
    high: 'Sugar has been running high — the range for diabetes starts at '
        '6.5%.',
    low: 'Unusually low averages, sometimes from frequent low-sugar '
        'episodes.',
  ),
  ['glucose', 'sugar']: MetricExplainer(
    what: 'Sugar in your blood at the moment it was drawn.',
    high: 'Diabetes or pre-diabetes, or simply eating before a test meant '
        'to be fasting.',
    low: 'Hypoglycaemia — can cause shakiness, sweating and confusion.',
  ),
  ['ldl']: MetricExplainer(
    what: 'The cholesterol that deposits in artery walls — the "bad" one.',
    high: 'Raises the long-term risk of heart attack and stroke.',
    low: 'Generally favourable for heart risk.',
  ),
  ['hdl']: MetricExplainer(
    what: 'The cholesterol that clears fat back out of arteries — the '
        '"good" one.',
    high: 'Generally protective.',
    low: 'Less protection against heart disease; exercise raises it.',
  ),
  ['triglyceride']: MetricExplainer(
    what: 'Fat carried in the blood, strongly affected by recent meals and '
        'alcohol.',
    high: 'Linked to heart risk, and at very high levels to pancreatitis.',
    low: 'Rarely a concern on its own.',
  ),
  ['cholesterol']: MetricExplainer(
    what: 'All the cholesterol in your blood added together.',
    high: 'Worth reading alongside LDL and HDL rather than on its own.',
    low: 'Rarely a concern on its own.',
  ),
  ['creatinine']: MetricExplainer(
    what: 'A waste product from muscle that healthy kidneys filter out.',
    high: 'Suggests the kidneys are filtering less well; dehydration and '
        'heavy muscle also raise it.',
    low: 'Common with low muscle mass, and not usually a problem.',
  ),
  ['urea', 'bun']: MetricExplainer(
    what: 'A waste product from protein that the kidneys clear.',
    high: 'Reduced kidney clearance, dehydration, or a high-protein diet.',
    low: 'Sometimes low protein intake or liver disease.',
  ),
  ['uricacid']: MetricExplainer(
    what: 'A waste product that forms crystals in joints when it builds up.',
    high: 'Associated with gout and kidney stones.',
    low: 'Rarely a concern.',
  ),
  ['sgpt', 'alt']: MetricExplainer(
    what: 'A liver enzyme that leaks into blood when liver cells are '
        'irritated.',
    high: 'Fatty liver, alcohol, viral hepatitis, or a reaction to a '
        'medicine.',
    low: 'Not clinically significant.',
  ),
  ['sgot', 'ast']: MetricExplainer(
    what: 'An enzyme from liver and muscle; read next to ALT.',
    high: 'Liver irritation, and sometimes muscle injury or heavy exercise.',
    low: 'Not clinically significant.',
  ),
  ['bilirubin']: MetricExplainer(
    what: 'The yellow pigment from broken-down red cells that the liver '
        'clears.',
    high: 'What turns eyes and skin yellow; liver or bile duct trouble, or '
        'harmless Gilbert\'s syndrome.',
    low: 'Not clinically significant.',
  ),
  ['albumin']: MetricExplainer(
    what: 'The main protein the liver makes, which holds fluid inside '
        'vessels.',
    high: 'Usually just dehydration.',
    low: 'Long-term liver or kidney disease, or poor nutrition.',
  ),
  ['tsh']: MetricExplainer(
    what: 'The pituitary\'s instruction to the thyroid — it rises when the '
        'thyroid is underperforming.',
    high: 'An underactive thyroid: tiredness, weight gain, feeling cold.',
    low: 'An overactive thyroid: palpitations, weight loss, anxiety.',
  ),
  ['t3', 't4', 'thyroxine']: MetricExplainer(
    what: 'The thyroid hormones themselves, which set your metabolic rate.',
    high: 'An overactive thyroid.',
    low: 'An underactive thyroid.',
  ),
  ['vitamind', '25hydroxy']: MetricExplainer(
    what: 'Vitamin D, which you make from sunlight and need for bone '
        'strength.',
    high: 'Almost always over-supplementation.',
    low: 'Very common; linked to bone pain, muscle weakness and fatigue.',
  ),
  ['b12']: MetricExplainer(
    what: 'A vitamin needed for nerves and for making red blood cells.',
    high: 'Usually supplements.',
    low: 'Causes tiredness, tingling in hands and feet, and anaemia; common '
        'on vegetarian diets.',
  ),
  ['ferritin']: MetricExplainer(
    what: 'Your stored iron — it falls before anaemia appears in the blood '
        'count.',
    high: 'Inflammation, liver disease, or iron overload.',
    low: 'Iron deficiency, the earliest sign of it.',
  ),
  ['crp']: MetricExplainer(
    what: 'A protein the liver releases within hours of inflammation '
        'starting.',
    high: 'Active infection or inflammation somewhere in the body.',
    low: 'Normal.',
  ),
  ['esr']: MetricExplainer(
    what: 'How fast red cells settle — a slower, broader signal of '
        'inflammation than CRP.',
    high: 'Infection, inflammation, or anaemia.',
    low: 'Normal.',
  ),
  ['sodium']: MetricExplainer(
    what: 'The salt balance that governs how much water your body holds.',
    high: 'Usually dehydration.',
    low: 'Too much water relative to salt; causes confusion when severe.',
  ),
  ['potassium']: MetricExplainer(
    what: 'The electrolyte that keeps heart and muscle rhythm steady.',
    high: 'Dangerous for heart rhythm; kidney trouble and some blood '
        'pressure medicines raise it.',
    low: 'Causes cramps and weakness, and also affects heart rhythm.',
  ),
  ['calcium']: MetricExplainer(
    what: 'The mineral behind bone strength, nerve signals and muscle '
        'contraction.',
    high: 'Parathyroid overactivity, or too much vitamin D.',
    low: 'Vitamin D deficiency or parathyroid problems; causes tingling and '
        'cramps.',
  ),
};
