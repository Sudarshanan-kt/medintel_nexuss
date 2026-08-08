import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../scan/domain/medicine.dart';
import '../domain/generic_swap.dart';

/// Estimates generic-equivalent savings for scanned medicines.
///
/// Served by the backend against its local model, same as [AssistantService]
/// — nothing here holds a provider key. Falls back to a small curated local
/// lookup of well-known brand → generic pairs when the backend or the model
/// can't be reached, the same "never fabricate, never crash" posture as the
/// rest of the app.
class SavingsService {
  SavingsService({required this.dio});

  final Dio dio;

  /// Looks up generic-swap suggestions for [medicines]. Returns one
  /// [GenericSwap] per input medicine (never throws).
  Future<List<GenericSwap>> findGenericSwaps(List<Medicine> medicines) async {
    if (medicines.isEmpty) return const [];

    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.savingsGenerics,
        options: Options(
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 15),
        ),
        data: {
          'medicines': [
            for (final m in medicines)
              {'id': m.id, 'name': m.name, 'strength': m.strength},
          ],
        },
      );

      final data = res.data?['data'];
      if (data is! Map) return _localFallback(medicines);
      // `checked: false` means the lookup never ran — the curated table
      // below is a better answer than an empty list.
      if (data['checked'] != true) return _localFallback(medicines);

      final parsed = _parseSwaps(data['swaps'], medicines);
      return parsed.isEmpty ? _localFallback(medicines) : parsed;
    } on DioException catch (e) {
      debugPrint('Savings request failed: ${e.message}');
      return _localFallback(medicines);
    } catch (e) {
      debugPrint('Savings parse failed: $e');
      return _localFallback(medicines);
    }
  }

  List<GenericSwap> _parseSwaps(Object? raw, List<Medicine> medicines) {
    if (raw is! List) return const [];
    final byId = {for (final m in medicines) m.id: m};
    final out = <GenericSwap>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final medicine = byId[entry['id']];
      if (medicine == null) continue;
      final generic = (entry['generic_name'] as String?)?.trim();
      out.add(
        GenericSwap(
          medicineId: medicine.id,
          brandName: medicine.name,
          genericName:
              (generic != null && generic.isNotEmpty) ? generic : medicine.name,
          savingsLowPercent: _clampPercent(entry['savings_low']),
          savingsHighPercent: _clampPercent(entry['savings_high']),
          note: (entry['note'] as String?)?.trim().isNotEmpty == true
              ? (entry['note'] as String).trim()
              : 'Ask your pharmacist if a generic version is available.',
        ),
      );
    }
    return out;
  }

  int _clampPercent(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return n.clamp(0, 90);
  }

  /// Small curated brand → generic lookup used when no LLM is reachable.
  /// Deliberately conservative: unmapped or already-generic names surface as
  /// "already generic" rather than a guessed number.
  static const Map<String, ({String generic, int low, int high, String note})>
      _knownBrands = {
    'crocin': (
      generic: 'Paracetamol',
      low: 40,
      high: 70,
      note: 'Same active ingredient, widely sold as a plain generic.',
    ),
    'calpol': (
      generic: 'Paracetamol',
      low: 40,
      high: 70,
      note: 'Same active ingredient, widely sold as a plain generic.',
    ),
    'combiflam': (
      generic: 'Ibuprofen + Paracetamol',
      low: 30,
      high: 50,
      note: 'Combination generic versions are commonly stocked.',
    ),
    'lipitor': (
      generic: 'Atorvastatin',
      low: 50,
      high: 80,
      note: 'One of the most substituted statins once off-patent.',
    ),
    'glucophage': (
      generic: 'Metformin',
      low: 40,
      high: 70,
      note: 'Metformin generics are inexpensive and widely available.',
    ),
    'nexium': (
      generic: 'Esomeprazole',
      low: 50,
      high: 75,
      note: 'Generic esomeprazole is a well-established substitute.',
    ),
    'augmentin': (
      generic: 'Amoxicillin + Clavulanic Acid',
      low: 30,
      high: 50,
      note: 'Generic combination versions are commonly stocked.',
    ),
    'amoxil': (
      generic: 'Amoxicillin',
      low: 30,
      high: 60,
      note: 'Amoxicillin is off-patent and broadly generic.',
    ),
    'voveran': (
      generic: 'Diclofenac',
      low: 30,
      high: 55,
      note: 'Widely available as a plain generic.',
    ),
  };

  List<GenericSwap> _localFallback(List<Medicine> medicines) {
    return [
      for (final m in medicines)
        if (_knownBrands[m.name.trim().toLowerCase()] case final b?)
          GenericSwap(
            medicineId: m.id,
            brandName: m.name,
            genericName: b.generic,
            savingsLowPercent: b.low,
            savingsHighPercent: b.high,
            note: b.note,
          )
        else
          GenericSwap(
            medicineId: m.id,
            brandName: m.name,
            genericName: m.name,
            savingsLowPercent: 0,
            savingsHighPercent: 0,
            note: 'No local match for this name — start the local AI model '
                'on the backend for a personalised estimate.',
          ),
    ];
  }
}

final savingsServiceProvider = Provider<SavingsService>((ref) {
  return SavingsService(dio: ref.watch(dioClientProvider));
});
