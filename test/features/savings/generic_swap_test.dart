import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/savings/domain/generic_swap.dart';

void main() {
  group('GenericSwap', () {
    test('isAlreadyGeneric is true when brand and generic names match', () {
      const swap = GenericSwap(
        medicineId: 'm1',
        brandName: 'Amoxicillin',
        genericName: 'Amoxicillin',
        savingsLowPercent: 0,
        savingsHighPercent: 0,
        note: 'Already generic.',
      );
      expect(swap.isAlreadyGeneric, isTrue);
    });

    test('isAlreadyGeneric ignores case', () {
      const swap = GenericSwap(
        medicineId: 'm1',
        brandName: 'paracetamol',
        genericName: 'Paracetamol',
        savingsLowPercent: 0,
        savingsHighPercent: 0,
        note: '',
      );
      expect(swap.isAlreadyGeneric, isTrue);
    });

    test('isAlreadyGeneric is false for a real brand/generic pair', () {
      const swap = GenericSwap(
        medicineId: 'm2',
        brandName: 'Lipitor',
        genericName: 'Atorvastatin',
        savingsLowPercent: 50,
        savingsHighPercent: 80,
        note: 'Off-patent statin.',
      );
      expect(swap.isAlreadyGeneric, isFalse);
    });

    test('savingsRangeLabel collapses equal bounds to a single figure', () {
      const swap = GenericSwap(
        medicineId: 'm3',
        brandName: 'X',
        genericName: 'Y',
        savingsLowPercent: 40,
        savingsHighPercent: 40,
        note: '',
      );
      expect(swap.savingsRangeLabel, '~40%');
    });

    test('savingsRangeLabel shows a range for differing bounds', () {
      const swap = GenericSwap(
        medicineId: 'm4',
        brandName: 'X',
        genericName: 'Y',
        savingsLowPercent: 50,
        savingsHighPercent: 80,
        note: '',
      );
      expect(swap.savingsRangeLabel, '50–80%');
    });
  });
}
