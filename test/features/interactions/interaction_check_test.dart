import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/interactions/domain/drug_interaction_result.dart';
import 'package:medintel_nexus/shared/widgets/risk_badge.dart';

/// The one thing this screen must never get wrong is letting an empty
/// result read as an all-clear. [InteractionCheck.isClear] is the single
/// gate on showing reassurance, so it carries that whole burden.
void main() {
  InteractionCheck check({
    bool checked = true,
    List<DrugInteraction> interactions = const [],
    List<String> unrecognized = const [],
    int ungraded = 0,
  }) =>
      InteractionCheck(
        checked: checked,
        interactions: interactions,
        unrecognized: unrecognized,
        ungradedPairCount: ungraded,
        disclaimer: '',
      );

  const interaction = DrugInteraction(
    medicineA: 'Warfarin',
    medicineB: 'Aspirin',
    risk: RiskLevel.severe,
    level: 'Major',
    mechanism: 'Both thin the blood.',
    recommendation: 'Ask your doctor.',
  );

  group('isClear — the only gate on reassurance', () {
    test('true when the check ran, found nothing, and knew every drug', () {
      expect(check().isClear, isTrue);
    });

    test('false when the check could not run', () {
      // An empty list because nothing was checked is not an all-clear.
      expect(check(checked: false).isClear, isFalse);
    });

    test('false when a drug was not recognised', () {
      // Nothing was checked for that drug, so "no interactions" is not a
      // statement about it.
      expect(check(unrecognized: ['Zorbtive9000']).isClear, isFalse);
    });

    test('false when interactions were found', () {
      expect(check(interactions: [interaction]).isClear, isFalse);
    });

    test('ungraded pairs alone do not withhold reassurance', () {
      // They are disclosed as a footnote instead. Treating them as warnings
      // was measured to bury the graded ones on a routine prescription.
      expect(check(ungraded: 8).isClear, isTrue);
    });
  });

  group('DrugInteraction', () {
    test('labels the pair for display', () {
      expect(interaction.pairLabel, 'Warfarin + Aspirin');
    });

    test('keeps the database grading distinct from the badge level', () {
      // Minor and Moderate share an amber badge, so the verbatim grading is
      // what stops "Minor" being shown as though it were "Moderate".
      const minor = DrugInteraction(
        medicineA: 'A',
        medicineB: 'B',
        risk: RiskLevel.moderate,
        level: 'Minor',
        mechanism: '',
        recommendation: '',
      );
      expect(minor.risk, RiskLevel.moderate);
      expect(minor.level, 'Minor');
    });
  });

  group('an unavailable check', () {
    test('carries no risk verdict at all', () {
      // Null rather than RiskLevel.none — "none" would render as a green
      // "No interaction" badge for a check that never ran.
      expect(check(checked: false).overallRisk, isNull);
    });
  });
}
