import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/scan/domain/dosage_format.dart';

void main() {
  group('expandFrequency', () {
    test('reads the morning-afternoon-night grid', () {
      expect(expandFrequency('1-0-1'), 'Morning & night');
      expect(expandFrequency('0-0-1'), 'Night');
      expect(expandFrequency('1-1-1'), 'Morning, afternoon & night');
    });

    test('reads Latin abbreviations, whatever their case', () {
      expect(expandFrequency('BD'), 'Twice daily');
      expect(expandFrequency('tds'), 'Three times a day');
      expect(expandFrequency('Od'), 'Once daily');
      expect(expandFrequency('SOS'), 'Only when needed');
    });

    test('keeps a qualifier around the shorthand', () {
      // "OD (night)" is a real thing prescriptions write; losing the
      // bracket would change when the patient takes it.
      expect(expandFrequency('OD (night)'), 'Once daily (night)');
    });

    test('never expands shorthand buried inside a longer word', () {
      // "od" inside "iodine" is not a dosing instruction.
      expect(expandFrequency('iodine'), 'iodine');
      expect(expandFrequency('as directed'), 'as directed');
    });

    test('passes unrecognised shorthand through untouched', () {
      // A patient can ask a pharmacist what this means; they cannot un-see
      // a confident wrong expansion.
      expect(expandFrequency('2-2-2-2'), '2-2-2-2');
      expect(expandFrequency('every 6 hours'), 'every 6 hours');
    });

    test('empty input stays empty', () {
      expect(expandFrequency(''), '');
      expect(expandFrequency('   '), '');
    });
  });

  group('formatDosageLine', () {
    test('joins the separated fields into one readable line', () {
      expect(
        formatDosageLine(
          frequency: '1-0-1',
          durationDays: 5,
          instructions: 'after food',
        ),
        'Morning & night · for 5 days · after food',
      );
    });

    test('omits fields the prescription never stated', () {
      expect(
        formatDosageLine(frequency: 'SOS', instructions: 'fever only'),
        'Only when needed · fever only',
      );
      expect(formatDosageLine(durationDays: 30), 'for 30 days');
    });

    test('a single day is not "1 days"', () {
      expect(formatDosageLine(durationDays: 1), 'for 1 day');
    });

    test('nothing stated produces an empty line, not stray separators', () {
      expect(formatDosageLine(), '');
      expect(formatDosageLine(frequency: '  ', instructions: ''), '');
    });
  });

  group('against values the real pipeline produced', () {
    // Captured from an end-to-end scan of a printed prescription through
    // Tesseract and the local model, so these are the exact strings the
    // backend hands over rather than idealised ones.
    test('a clean read becomes plain language', () {
      expect(
        formatDosageLine(
          frequency: 'BD',
          durationDays: 30,
          instructions: 'with meals',
        ),
        'Twice daily · for 30 days · with meals',
      );
      expect(
        formatDosageLine(frequency: 'OD (night)', durationDays: 30),
        'Once daily (night) · for 30 days',
      );
    });

    test('an OCR-garbled rhythm is shown as-is, not guessed at', () {
      // Tesseract read "1-0-0" as "10-0" and "TDS" as "Tos" on a degraded
      // capture. Both are flagged for review by the confidence gate; the
      // display must not paper over them with an invented reading.
      expect(
        formatDosageLine(frequency: '10-0', instructions: 'continue'),
        '10-0 · continue',
      );
      expect(
        formatDosageLine(
          frequency: 'Tos',
          durationDays: 14,
          instructions: 'empty stomach',
        ),
        'Tos · for 14 days · empty stomach',
      );
    });
  });
}
