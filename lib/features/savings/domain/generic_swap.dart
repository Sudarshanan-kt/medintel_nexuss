/// A suggested generic equivalent for a scanned/prescribed medicine, with a
/// rough typical cost-saving band. Percentages are educational estimates —
/// never a specific price quote — since no live pricing feed is integrated.
class GenericSwap {
  const GenericSwap({
    required this.medicineId,
    required this.brandName,
    required this.genericName,
    required this.savingsLowPercent,
    required this.savingsHighPercent,
    required this.note,
  });

  final String medicineId;
  final String brandName;
  final String genericName;

  /// Typical low/high ends of the cost-saving band, e.g. 20–60.
  final int savingsLowPercent;
  final int savingsHighPercent;

  /// Short plain-language context, e.g. "Same active ingredient, widely
  /// available as a generic."
  final String note;

  /// True when the brand and generic name are effectively the same drug —
  /// i.e. there's no real swap to suggest.
  bool get isAlreadyGeneric =>
      brandName.trim().toLowerCase() == genericName.trim().toLowerCase();

  String get savingsRangeLabel => savingsLowPercent == savingsHighPercent
      ? '~$savingsLowPercent%'
      : '$savingsLowPercent–$savingsHighPercent%';
}
