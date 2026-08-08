import '../../../shared/widgets/risk_badge.dart';

/// The editable parts of a [Medicine], as the review UI groups them.
///
/// The OCR pipeline scores six fields; this collapses them onto the three
/// inputs the patient actually sees, so a low score on `frequency` or
/// `instructions` lights up the one dosage box they'd correct it in.
enum MedicineField {
  name,
  strength,
  dosage;

  /// Maps a backend field key onto the box it's edited in. Unknown keys are
  /// dropped rather than guessed at.
  static MedicineField? fromApiKey(String key) => switch (key) {
        'raw_name' || 'normalized_name' => MedicineField.name,
        'strength' => MedicineField.strength,
        'frequency' || 'duration_days' || 'instructions' => MedicineField.dosage,
        _ => null,
      };

  String get label => switch (this) {
        MedicineField.name => 'Name',
        MedicineField.strength => 'Strength',
        MedicineField.dosage => 'Dosage',
      };
}

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
    this.uncertainFields = const {},
    this.blockingFields = const {},
    this.userCorrected = false,
    this.interactionsChecked = true,
  });

  final String id;
  final String name;
  final String strength;
  final String dosageLine;
  final RiskLevel riskLevel;
  final String? riskNote;
  final double confidence;

  /// Fields the OCR wasn't confident it read correctly — highlighted in the
  /// review UI so the patient's attention lands where it's needed.
  final Set<MedicineField> uncertainFields;

  /// The subset of [uncertainFields] serious enough to hold up risk
  /// analysis: an uncertain drug name or strength.
  final Set<MedicineField> blockingFields;

  /// True once the patient typed over what OCR read.
  final bool userCorrected;

  /// False when the interaction database has never heard of this drug, so
  /// nothing was checked for it.
  ///
  /// This must reach the UI. [riskLevel] is [RiskLevel.none] for an
  /// unchecked medicine exactly as it is for one that came back clean, and
  /// the badge for "none" reads "No interaction" over a green tick — which
  /// would be a confident all-clear the check never actually made.
  final bool interactionsChecked;

  bool get isLowConfidence => uncertainFields.isNotEmpty || confidence < 0.7;

  bool isUncertain(MedicineField field) => uncertainFields.contains(field);

  Medicine copyWith({
    String? name,
    String? strength,
    String? dosageLine,
    RiskLevel? riskLevel,
    String? riskNote,
    double? confidence,
    Set<MedicineField>? uncertainFields,
    Set<MedicineField>? blockingFields,
    bool? userCorrected,
    bool? interactionsChecked,
  }) =>
      Medicine(
        id: id,
        name: name ?? this.name,
        strength: strength ?? this.strength,
        dosageLine: dosageLine ?? this.dosageLine,
        riskLevel: riskLevel ?? this.riskLevel,
        riskNote: riskNote ?? this.riskNote,
        confidence: confidence ?? this.confidence,
        uncertainFields: uncertainFields ?? this.uncertainFields,
        blockingFields: blockingFields ?? this.blockingFields,
        userCorrected: userCorrected ?? this.userCorrected,
        interactionsChecked: interactionsChecked ?? this.interactionsChecked,
      );

  /// The state a medicine is in once the patient has confirmed it: nothing
  /// left to flag, whatever the OCR originally thought.
  Medicine confirmed({bool corrected = false}) => copyWith(
        confidence: 1.0,
        uncertainFields: const {},
        blockingFields: const {},
        userCorrected: userCorrected || corrected,
      );
}
