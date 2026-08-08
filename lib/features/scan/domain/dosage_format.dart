/// Turns prescription shorthand into something a patient can read.
///
/// The backend deliberately keeps `frequency` exactly as the page writes it
/// — "BD", "1-0-1" — because field confidence is measured by matching the
/// value back to the words Tesseract read, and a paraphrase has nothing on
/// the page supporting it. That makes the stored value good provenance and
/// poor patient copy, so the expansion happens here, at the point of
/// display, rather than in the pipeline.
///
/// Anything unrecognised is passed through untouched. Inventing a reading
/// for shorthand nobody recognises would be worse than showing the original:
/// a patient can ask a pharmacist what "1-0-1-0" means, but not un-see a
/// confident wrong expansion.
library;

/// Latin dosing abbreviations, and the Indian morning-afternoon-night grid.
const Map<String, String> _shorthand = {
  // Morning-afternoon-night, the notation used on most Indian prescriptions.
  '1-0-0': 'Morning',
  '0-1-0': 'Afternoon',
  '0-0-1': 'Night',
  '1-1-0': 'Morning & afternoon',
  '1-0-1': 'Morning & night',
  '0-1-1': 'Afternoon & night',
  '1-1-1': 'Morning, afternoon & night',
  '2-0-2': 'Two morning & two night',
  '1-0-1-0': 'Morning & evening',

  // Latin abbreviations.
  'od': 'Once daily',
  'bd': 'Twice daily',
  'bid': 'Twice daily',
  'tds': 'Three times a day',
  'tid': 'Three times a day',
  'qid': 'Four times a day',
  'qds': 'Four times a day',
  'hs': 'At bedtime',
  'nocte': 'At night',
  'mane': 'In the morning',
  'stat': 'Immediately',
  'sos': 'Only when needed',
  'prn': 'As needed',
  'ac': 'Before food',
  'pc': 'After food',
};

/// Matches a shorthand token: either a dose grid (1-0-1) or a run of
/// letters. Bounded so "od" inside "iodine" is never touched.
final RegExp _token = RegExp(r'\b(\d+(?:-\d+)+|[A-Za-z]+)\b');

/// Expands the dosing shorthand in [frequency] for display.
///
/// Qualifiers around the shorthand survive — "OD (night)" becomes
/// "Once daily (night)" rather than losing the part in brackets.
String expandFrequency(String frequency) {
  if (frequency.trim().isEmpty) return '';
  return frequency.replaceAllMapped(_token, (match) {
    final token = match[0]!;
    return _shorthand[token.toLowerCase()] ?? token;
  });
}

/// Builds the human-readable dosage line shown on a medicine card, from the
/// pipeline's separated fields.
String formatDosageLine({
  String? frequency,
  int? durationDays,
  String? instructions,
}) {
  final parts = <String>[
    if (frequency != null && frequency.trim().isNotEmpty)
      expandFrequency(frequency.trim()),
    if (durationDays != null)
      durationDays == 1 ? 'for 1 day' : 'for $durationDays days',
    if (instructions != null && instructions.trim().isNotEmpty)
      instructions.trim(),
  ];
  return parts.join(' · ');
}
