import '../../../shared/widgets/risk_badge.dart';

/// A structured medicine extracted from or attached to a prescription.
class Medicine {
  const Medicine({
    required this.id,
    required this.name,
    required this.strength,
    required this.dosageLine,
    required this.riskLevel,
    this.riskNote,
    this.confidence = 1.0,
  });

  final String id;
  final String name;
  final String strength;
  final String dosageLine;
  final RiskLevel riskLevel;
  final String? riskNote;
  final double confidence;

  bool get isLowConfidence => confidence < 0.7;

  Medicine copyWith({
    String? name,
    String? strength,
    String? dosageLine,
    RiskLevel? riskLevel,
    String? riskNote,
    double? confidence,
  }) =>
      Medicine(
        id: id,
        name: name ?? this.name,
        strength: strength ?? this.strength,
        dosageLine: dosageLine ?? this.dosageLine,
        riskLevel: riskLevel ?? this.riskLevel,
        riskNote: riskNote ?? this.riskNote,
        confidence: confidence ?? this.confidence,
      );
}
