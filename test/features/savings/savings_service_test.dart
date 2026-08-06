import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/features/savings/data/savings_service.dart';
import 'package:medintel_nexus/features/scan/domain/medicine.dart';
import 'package:medintel_nexus/shared/widgets/risk_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No API key is ever configured in this test environment, so every call
  // resolves through the local fallback table — deterministic, no network.
  final service = SavingsService(dio: Dio(), storage: const FlutterSecureStorage());

  Medicine medicine(String name) => Medicine(
        id: name,
        name: name,
        strength: '500 mg',
        dosageLine: '1 tab · 2×/day',
        riskLevel: RiskLevel.none,
      );

  group('SavingsService local fallback', () {
    test('known brand resolves to its generic with a savings band', () async {
      final swaps = await service.findGenericSwaps([medicine('Lipitor')]);
      expect(swaps, hasLength(1));
      expect(swaps.single.genericName, 'Atorvastatin');
      expect(swaps.single.isAlreadyGeneric, isFalse);
      expect(swaps.single.savingsLowPercent, greaterThan(0));
    });

    test('unmapped name surfaces as already-generic, no fabricated number',
        () async {
      final swaps = await service.findGenericSwaps([medicine('Zorbtive9000')]);
      expect(swaps, hasLength(1));
      expect(swaps.single.isAlreadyGeneric, isTrue);
      expect(swaps.single.savingsLowPercent, 0);
      expect(swaps.single.savingsHighPercent, 0);
    });

    test('brand match is case-insensitive', () async {
      final swaps = await service.findGenericSwaps([medicine('lipitor')]);
      expect(swaps.single.genericName, 'Atorvastatin');
    });

    test('empty input returns empty output', () async {
      final swaps = await service.findGenericSwaps([]);
      expect(swaps, isEmpty);
    });

    test('one entry per input medicine, in order', () async {
      final swaps = await service.findGenericSwaps(
        [medicine('Crocin'), medicine('Unknown123'), medicine('Nexium')],
      );
      expect(swaps, hasLength(3));
      expect(swaps[0].genericName, 'Paracetamol');
      expect(swaps[1].isAlreadyGeneric, isTrue);
      expect(swaps[2].genericName, 'Esomeprazole');
    });
  });
}
