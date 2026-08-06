import '../domain/medical_report.dart';

/// An actionable "how to improve" tip for an out-of-range lab value.
class HealthTip {
  const HealthTip({
    required this.label,
    required this.direction, // 'Lower' | 'Raise'
    required this.advice,
  });

  final String label;
  final String direction;
  final String advice;

  String get headline => '$direction your $label';
}

/// Maps out-of-range lab metrics to plain-language lifestyle guidance.
///
/// This is general wellness information, not medical advice — the UI always
/// pairs it with a "confirm with your doctor" note.
abstract final class HealthAdvice {
  /// Returns tips for every out-of-range metric in [report].
  static List<HealthTip> forReport(MedicalReport report) {
    final tips = <HealthTip>[];
    for (final m in report.metrics) {
      if (!m.isOutOfRange) continue;
      final high = m.value > m.refHigh;
      final tip = _forMetric(m.label, high);
      if (tip != null) tips.add(tip);
    }
    return tips;
  }

  static HealthTip? _forMetric(String rawLabel, bool high) {
    final label = rawLabel.toLowerCase();

    if (label.contains('tsh')) {
      return HealthTip(
        label: rawLabel,
        direction: high ? 'Lower' : 'Raise',
        advice: high
            ? 'A high TSH points to an underactive thyroid. Ask your doctor about a repeat thyroid test; if treatment is needed it is usually a simple daily tablet. Take iodine-rich foods in moderation and keep regular sleep.'
            : 'A low TSH can mean an overactive thyroid. Avoid excess iodine/kelp supplements and review any thyroid medication dose with your doctor.',
      );
    }
    if (label.contains('uric')) {
      return const HealthTip(
        label: 'Uric Acid',
        direction: 'Lower',
        advice:
            'Drink plenty of water, and cut back on red meat, organ meats, shellfish, alcohol (especially beer) and sugary/fructose drinks. Cherries, low-fat dairy and weight loss help lower uric acid.',
      );
    }
    if (label.contains('ldl') ||
        label.contains('non-hdl') ||
        (label.contains('cholesterol') && !label.contains('hdl'))) {
      return HealthTip(
        label: rawLabel,
        direction: 'Lower',
        advice:
            'Reduce saturated fat (fried food, ghee, fatty meat, full-fat dairy) and avoid trans fats. Eat more oats, beans, nuts, fruits and vegetables, use olive/sunflower oil, and aim for 30 minutes of activity most days.',
      );
    }
    if (label.contains('hdl')) {
      return const HealthTip(
        label: 'HDL Cholesterol',
        direction: 'Raise',
        advice:
            'Raise "good" HDL with regular aerobic exercise, healthy fats (nuts, olive oil, fish), and stopping smoking.',
      );
    }
    if (label.contains('triglyceride')) {
      return const HealthTip(
        label: 'Triglycerides',
        direction: 'Lower',
        advice:
            'Cut sugar, refined carbs and alcohol, lose excess weight, and add omega-3 rich fish and regular exercise.',
      );
    }
    if (label.contains('esr') || label.contains('crp')) {
      return HealthTip(
        label: rawLabel,
        direction: 'Lower',
        advice:
            'A raised inflammatory marker is non-specific. Treat any underlying infection, eat an anti-inflammatory diet (fruit, vegetables, omega-3), stay active and ask your doctor if it stays high.',
      );
    }
    if (label.contains('haemoglobin') || label.contains('hemoglobin')) {
      return HealthTip(
        label: rawLabel,
        direction: high ? 'Lower' : 'Raise',
        advice: high
            ? 'Stay well hydrated and discuss persistently high haemoglobin with your doctor.'
            : 'Boost iron with leafy greens, legumes, dates and lean meat, paired with vitamin-C foods; ask your doctor about iron studies.',
      );
    }
    if (label.contains('glucose') ||
        label.contains('hba1c') ||
        label.contains('sugar')) {
      return HealthTip(
        label: rawLabel,
        direction: 'Lower',
        advice:
            'Reduce refined carbs and sugary drinks, choose whole grains and vegetables, exercise regularly and maintain a healthy weight.',
      );
    }

    // Generic fallback so every out-of-range value still gets guidance.
    return HealthTip(
      label: rawLabel,
      direction: high ? 'Lower' : 'Raise',
      advice: high
          ? 'This value is above the reference range. A balanced diet, regular exercise, good hydration and a follow-up with your doctor are recommended.'
          : 'This value is below the reference range. A balanced, nutrient-rich diet and a follow-up with your doctor are recommended.',
    );
  }
}
