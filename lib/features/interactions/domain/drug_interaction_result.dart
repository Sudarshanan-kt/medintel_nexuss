import '../../../shared/widgets/risk_badge.dart';

/// One interacting pair, as graded by the backend's interaction database.
///
/// [level] is the database's own wording (Major / Moderate / Minor), kept
/// verbatim so a verdict stays traceable to its source. [risk] is the app's
/// three-level vocabulary that drives the badge colour — Minor maps to
/// [RiskLevel.moderate] rather than none, because a minor interaction is
/// still an interaction.
class DrugInteraction {
  const DrugInteraction({
    required this.medicineA,
    required this.medicineB,
    required this.risk,
    required this.level,
    required this.mechanism,
    required this.recommendation,
    this.explained = true,
  });

  final String medicineA;
  final String medicineB;
  final RiskLevel risk;
  final String level;

  /// Plain-language explanation of why the two interact.
  final String mechanism;

  /// What the patient should actually do about it.
  final String recommendation;

  /// False when [mechanism] is the fixed fallback text rather than a
  /// generated explanation. The severity above it is unaffected either way —
  /// it comes from the database, not from whatever wrote this sentence.
  final bool explained;

  String get pairLabel => '$medicineA + $medicineB';
}

/// The result of one interaction check.
///
/// Three fields exist purely so an empty [interactions] list can never be
/// mistaken for an all-clear, which is the failure mode this whole screen
/// has to avoid:
///
/// * [checked] false — the check could not run at all.
/// * [unrecognized] — drugs the database has never heard of. Nothing was
///   checked for those.
/// * [ungradedPairCount] — pairs the database lists without an established
///   severity. Not warnings, but not nothing either.
class InteractionCheck {
  const InteractionCheck({
    required this.checked,
    required this.interactions,
    required this.disclaimer,
    this.overallRisk,
    this.unrecognized = const [],
    this.ungradedPairCount = 0,
    this.source,
  });

  final bool checked;
  final List<DrugInteraction> interactions;
  final String disclaimer;

  /// Null when [checked] is false — never "none", which would read as safe.
  final RiskLevel? overallRisk;

  final List<String> unrecognized;
  final int ungradedPairCount;

  /// Which dataset answered, for attribution.
  final String? source;

  /// True only when the check ran, every drug was recognised, and nothing
  /// was found. The only circumstance in which reassurance is honest.
  bool get isClear =>
      checked && interactions.isEmpty && unrecognized.isEmpty;
}
