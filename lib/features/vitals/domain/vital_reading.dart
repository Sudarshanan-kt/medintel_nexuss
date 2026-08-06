/// A single self-logged vital reading — blood pressure, weight, or blood
/// sugar. Distinct from MedicalReport.metrics (which are OCR'd from a lab
/// document): this is the patient's own ongoing journal over time.
enum VitalType {
  bloodPressure('Blood pressure', 'mmHg'),
  weight('Weight', 'kg'),
  bloodSugar('Blood sugar', 'mg/dL');

  const VitalType(this.label, this.unit);
  final String label;
  final String unit;
}

class VitalReading {
  const VitalReading({
    required this.id,
    required this.type,
    required this.value,
    this.secondaryValue,
    required this.timestamp,
    this.note,
  });

  final String id;
  final VitalType type;

  /// Primary value. For blood pressure this is the systolic reading.
  final double value;

  /// Blood pressure's diastolic reading — null for weight/blood sugar.
  final double? secondaryValue;

  final DateTime timestamp;
  final String? note;

  /// Display string, e.g. "120/80" for BP or "68.5" for weight.
  String get displayValue => type == VitalType.bloodPressure
      ? '${value.toStringAsFixed(0)}/${(secondaryValue ?? 0).toStringAsFixed(0)}'
      : (value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1));

  /// Rough, non-diagnostic in-range check — purely a visual cue, never a
  /// medical judgement. Reference ranges are generic adult defaults.
  bool get isInNormalRange {
    switch (type) {
      case VitalType.bloodPressure:
        return value >= 90 &&
            value <= 120 &&
            (secondaryValue ?? 0) >= 60 &&
            (secondaryValue ?? 0) <= 80;
      case VitalType.bloodSugar:
        return value >= 70 && value <= 100;
      case VitalType.weight:
        return true; // no universal reference range — always neutral
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'value': value,
        'secondaryValue': secondaryValue,
        'timestamp': timestamp.toIso8601String(),
        'note': note,
      };

  static VitalReading fromJson(Map<String, dynamic> j) => VitalReading(
        id: (j['id'] as String?) ?? '${DateTime.now().microsecondsSinceEpoch}',
        type: VitalType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => VitalType.weight,
        ),
        value: (j['value'] as num?)?.toDouble() ?? 0,
        secondaryValue: (j['secondaryValue'] as num?)?.toDouble(),
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
        note: j['note'] as String?,
      );
}
