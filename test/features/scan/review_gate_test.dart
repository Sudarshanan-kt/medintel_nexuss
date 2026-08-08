import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/scan/domain/medicine.dart';
import 'package:medintel_nexus/features/scan/domain/prescription_scan.dart';
import 'package:medintel_nexus/shared/widgets/risk_badge.dart';

Medicine _medicine({
  String id = 'm_1',
  String name = 'Amoxicillin',
  Set<MedicineField> uncertain = const {},
  Set<MedicineField> blocking = const {},
}) =>
    Medicine(
      id: id,
      name: name,
      strength: '500 mg',
      dosageLine: 'twice daily',
      riskLevel: RiskLevel.none,
      uncertainFields: uncertain,
      blockingFields: blocking,
    );

PrescriptionScan _scan({
  required List<Medicine> medicines,
  bool verified = false,
  ScanStatus status = ScanStatus.analyzed,
}) =>
    PrescriptionScan(
      id: 's_1',
      imageRef: '/tmp/rx.jpg',
      status: status,
      medicines: medicines,
      verified: verified,
    );

void main() {
  group('PrescriptionScan review gate', () {
    test('an unverified analyzed scan needs review', () {
      final scan = _scan(
        medicines: [_medicine(uncertain: {MedicineField.name})],
      );

      expect(scan.needsReview, isTrue);
    });

    test('a verified scan does not', () {
      final scan = _scan(medicines: [_medicine()], verified: true);

      expect(scan.needsReview, isFalse);
    });

    test('a scan still processing is not asking for confirmation yet', () {
      final scan = _scan(medicines: const [], status: ScanStatus.processing);

      expect(scan.needsReview, isFalse);
    });

    test('a scan that extracted nothing has nothing to confirm', () {
      // The screen routes this to manual entry instead — a review prompt
      // over an empty list would be a dead end.
      final scan = _scan(medicines: const []);

      expect(scan.needsReview, isFalse);
    });

    test('counts every uncertain field across all medicines', () {
      final scan = _scan(
        medicines: [
          _medicine(
            uncertain: {MedicineField.name, MedicineField.strength},
          ),
          _medicine(id: 'm_2', uncertain: {MedicineField.dosage}),
          _medicine(id: 'm_3'),
        ],
      );

      expect(scan.uncertainFieldCount, 3);
    });
  });

  group('Medicine confirmation', () {
    test('confirming clears every flag and maxes the confidence', () {
      final confirmed = _medicine(
        uncertain: {MedicineField.name},
        blocking: {MedicineField.name},
      ).confirmed(corrected: true);

      expect(confirmed.uncertainFields, isEmpty);
      expect(confirmed.blockingFields, isEmpty);
      expect(confirmed.confidence, 1.0);
      expect(confirmed.userCorrected, isTrue);
      expect(confirmed.isLowConfidence, isFalse);
    });

    test('accepting an entry untouched is not recorded as a correction', () {
      final confirmed = _medicine(uncertain: {MedicineField.name}).confirmed();

      expect(confirmed.uncertainFields, isEmpty);
      expect(confirmed.userCorrected, isFalse);
    });

    test('confirming keeps an earlier correction on the record', () {
      final corrected = _medicine().confirmed(corrected: true);

      expect(corrected.confirmed().userCorrected, isTrue);
    });
  });

  group('MedicineField', () {
    test('both name keys collapse onto the one box the patient edits', () {
      expect(MedicineField.fromApiKey('raw_name'), MedicineField.name);
      expect(MedicineField.fromApiKey('normalized_name'), MedicineField.name);
    });

    test('every dosage-ish field points at the dosage box', () {
      for (final key in ['frequency', 'duration_days', 'instructions']) {
        expect(MedicineField.fromApiKey(key), MedicineField.dosage);
      }
    });

    test('an unrecognised key is dropped rather than guessed at', () {
      expect(MedicineField.fromApiKey('route'), isNull);
    });
  });
}
