/// The outcome of checking one pair of medicines against FDA drug label
/// text (see `InteractionRepository`).
///
/// This is a text-search result, not a clinically-scored severity
/// classification: [excerpt] is the sentence pulled from [mentionedIn]'s
/// own FDA label where the other drug's name appears. A null [excerpt]
/// means no mention was found in either direction — which is evidence of
/// absence, not proof of safety, and the UI must say so.
class DrugInteractionResult {
  const DrugInteractionResult({
    required this.medicineA,
    required this.medicineB,
    required this.found,
    this.excerpt,
    this.mentionedIn,
  });

  final String medicineA;
  final String medicineB;
  final bool found;

  /// The sentence(s) containing the match, pulled verbatim from the label.
  final String? excerpt;

  /// Which of the two drugs' label text the excerpt came from.
  final String? mentionedIn;
}

/// One selected medicine's resolution against RxNorm + its FDA label
/// interaction section, cached for the duration of one check so pairwise
/// comparisons don't refetch.
class ResolvedMedicine {
  const ResolvedMedicine({
    required this.inputName,
    required this.matchedName,
    required this.interactionsText,
  });

  /// What the user typed / selected.
  final String inputName;

  /// RxNorm's resolved generic (ingredient) name, if found — this is what
  /// gets searched for in the *other* drug's label text, since labels
  /// overwhelmingly refer to ingredients rather than brand names.
  final String? matchedName;

  /// Full text of this drug's own "DRUG INTERACTIONS" label section, or
  /// null if no FDA label was found for it at all.
  final String? interactionsText;
}
