import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/dio_client.dart';
import '../../scan/domain/medicine.dart';
import '../domain/generic_swap.dart';

/// Estimates generic-equivalent savings for scanned medicines.
///
/// Same resolution order and provider as [AssistantService] (Groq, Llama
/// 3.3 70B) — deliberately reuses its stored API key so the user never has
/// to configure this twice. Falls back to a small curated local lookup of
/// well-known brand → generic pairs when no key is set or the call fails,
/// same "never fabricate, never crash" posture as the rest of the app.
class SavingsService {
  SavingsService({required this.dio, required this.storage});

  final Dio dio;
  final FlutterSecureStorage storage;

  static const String _kGroqApiKey = 'mn_groq_api_key';
  static const String _envKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: '');
  static const String _endpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';

  Future<String?> _apiKey() async {
    final stored = await storage.read(key: _kGroqApiKey);
    if (stored != null && stored.isNotEmpty) return stored;
    if (_envKey.isNotEmpty) return _envKey;
    return null;
  }

  /// Looks up generic-swap suggestions for [medicines]. Returns one
  /// [GenericSwap] per input medicine (never throws).
  Future<List<GenericSwap>> findGenericSwaps(List<Medicine> medicines) async {
    if (medicines.isEmpty) return const [];

    String? apiKey;
    try {
      apiKey = await _apiKey();
    } catch (e) {
      debugPrint('Savings: reading stored API key failed: $e');
    }
    if (apiKey == null) return _localFallback(medicines);

    try {
      final list = medicines
          .map((m) => '- id="${m.id}" name="${m.name}" strength="${m.strength}"')
          .join('\n');

      final res = await dio.post<String>(
        _endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 15),
        ),
        data: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': 'Medicines:\n$list'},
          ],
          'temperature': 0.2,
          'max_tokens': 800,
          'response_format': {'type': 'json_object'},
        }),
      );

      final json = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) return _localFallback(medicines);
      final content =
          ((choices.first as Map)['message'] as Map?)?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        return _localFallback(medicines);
      }

      final parsed = _parseResponse(content, medicines);
      return parsed.isEmpty ? _localFallback(medicines) : parsed;
    } on DioException catch (e) {
      debugPrint('Groq savings request failed: ${e.message}');
      return _localFallback(medicines);
    } catch (e) {
      debugPrint('Groq savings parse failed: $e');
      return _localFallback(medicines);
    }
  }

  static const String _systemPrompt = '''
You are a pharmacology reference assistant. For each medicine given (by brand
or generic name), identify its generic (INN) name and a realistic typical
cost-saving percentage range if the patient switched from a common branded
version to the generic version, in a typical retail pharmacy market.

Respond with ONLY a JSON object of this exact shape, no prose:
{"swaps": [
  {"id": "<the id given>", "generic_name": "<INN name>", "savings_low": <int 0-90>, "savings_high": <int 0-90>, "note": "<one short plain-language sentence>"}
]}

If the medicine given is already a generic/INN name with no distinct brand
premium to speak of, still return an entry with savings_low and savings_high
both 0, and a short reassuring note that it's already the generic form.
Never invent a specific currency price — percentages only.
''';

  List<GenericSwap> _parseResponse(String content, List<Medicine> medicines) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final swaps = (json['swaps'] as List?) ?? const [];
      final byId = {for (final m in medicines) m.id: m};
      final out = <GenericSwap>[];
      for (final raw in swaps) {
        if (raw is! Map) continue;
        final id = raw['id'] as String?;
        final medicine = id == null ? null : byId[id];
        if (medicine == null) continue;
        out.add(
          GenericSwap(
            medicineId: medicine.id,
            brandName: medicine.name,
            genericName: (raw['generic_name'] as String?)?.trim().isNotEmpty ==
                    true
                ? (raw['generic_name'] as String).trim()
                : medicine.name,
            savingsLowPercent: _clampPercent(raw['savings_low']),
            savingsHighPercent: _clampPercent(raw['savings_high']),
            note: (raw['note'] as String?)?.trim().isNotEmpty == true
                ? (raw['note'] as String).trim()
                : 'Ask your pharmacist if a generic version is available.',
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('Savings response parse error: $e');
      return const [];
    }
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
            note: 'No local match for this name — connect an AI key in '
                'Assistant settings for a personalised estimate.',
          ),
    ];
  }
}

final savingsServiceProvider = Provider<SavingsService>((ref) {
  return SavingsService(
    dio: Dio(),
    storage: ref.watch(secureStorageProvider),
  );
});
