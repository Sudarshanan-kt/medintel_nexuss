import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/drug_interaction_result.dart';

/// Checks medicine pairs against real FDA drug label text.
///
/// The NIH's old purpose-built Drug-Drug Interaction API (part of RxNav)
/// was discontinued January 2024, and DrugBank's free interaction checker
/// is being retired in March 2026 — so there is currently no free,
/// structured, severity-scored interaction API left to call. Instead this
/// assembles the same answer from two still-live NIH/FDA sources:
///  1. RxNorm (`rxnav.nlm.nih.gov`) — resolves whatever name the user typed
///     or picked (brand or generic) to its RxNorm ingredient name, since
///     FDA labels describe interactions by ingredient, not brand.
///  2. openFDA's structured product labels (`api.fda.gov/drug/label.json`)
///     — pulls each drug's own "DRUG INTERACTIONS" section, then checks
///     whether the other drug's resolved name appears in it.
///
/// This is real, sourced text — never LLM-generated — but it is a text
/// search, not a clinical interaction engine: it can miss interactions
/// phrased around a drug class rather than a specific ingredient name, and
/// a "no mention found" result is not the same as "confirmed safe". The UI
/// must carry that caveat prominently; this repository only surfaces what
/// the labels actually say.
class InteractionRepository {
  InteractionRepository(this._dio);

  final Dio _dio;

  /// Resolves [name] to its RxNorm ingredient name and fetches its FDA
  /// label's interactions section. Never throws — failures just leave the
  /// corresponding field null so the caller can show "no data" instead of
  /// crashing the whole check over one bad lookup.
  Future<ResolvedMedicine> resolve(String name) async {
    final ingredientName = await _resolveIngredientName(name);
    final interactionsText =
        await _fetchInteractionsSection(ingredientName ?? name);
    return ResolvedMedicine(
      inputName: name,
      matchedName: ingredientName,
      interactionsText: interactionsText,
    );
  }

  /// Brand or misspelled name → RxNorm's generic ingredient name.
  /// e.g. "Tylenol" → "acetaminophen".
  Future<String?> _resolveIngredientName(String name) async {
    try {
      final approx = await _dio.get<Map<String, dynamic>>(
        'https://rxnav.nlm.nih.gov/REST/approximateTerm.json',
        queryParameters: {'term': name, 'maxEntries': 1},
      );
      final candidates = (approx.data?['approximateGroup']
          as Map<String, dynamic>?)?['candidate'] as List?;
      final rxcui = candidates?.isNotEmpty == true
          ? candidates!.first['rxcui'] as String?
          : null;
      if (rxcui == null) return null;

      final related = await _dio.get<Map<String, dynamic>>(
        'https://rxnav.nlm.nih.gov/REST/rxcui/$rxcui/related.json',
        queryParameters: {'tty': 'IN'},
      );
      final groups = (related.data?['relatedGroup']
          as Map<String, dynamic>?)?['conceptGroup'] as List?;
      for (final group in groups ?? const []) {
        final props =
            (group as Map<String, dynamic>)['conceptProperties'] as List?;
        final first = props?.isNotEmpty == true
            ? props!.first as Map<String, dynamic>
            : null;
        final resolved = first?['name'] as String?;
        if (resolved != null && resolved.isNotEmpty) return resolved;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the "DRUG INTERACTIONS" free-text section of [drugName]'s
  /// FDA label. Tries generic name first, then brand name.
  Future<String?> _fetchInteractionsSection(String drugName) async {
    for (final field in ['openfda.generic_name', 'openfda.brand_name']) {
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          'https://api.fda.gov/drug/label.json',
          queryParameters: {
            'search': '$field:"${drugName.toLowerCase()}"',
            'limit': 1,
          },
        );
        final results = res.data?['results'] as List?;
        if (results == null || results.isEmpty) continue;
        final sections = (results.first
            as Map<String, dynamic>)['drug_interactions'] as List?;
        if (sections != null && sections.isNotEmpty) {
          return sections.join(' ');
        }
      } catch (_) {
        // Try the next field / give up gracefully.
      }
    }
    return null;
  }

  /// Checks every pair among [medicineNames] for a mention of one in the
  /// other's FDA label interactions text.
  Future<List<DrugInteractionResult>> checkInteractions(
    List<String> medicineNames,
  ) async {
    final unique = medicineNames.toSet().toList();
    final resolved = await Future.wait(unique.map(resolve));

    final results = <DrugInteractionResult>[];
    for (var i = 0; i < resolved.length; i++) {
      for (var j = i + 1; j < resolved.length; j++) {
        results.add(_comparePair(resolved[i], resolved[j]));
      }
    }
    return results;
  }

  DrugInteractionResult _comparePair(ResolvedMedicine a, ResolvedMedicine b) {
    final aExcerpt = _findMention(a.interactionsText, b);
    if (aExcerpt != null) {
      return DrugInteractionResult(
        medicineA: a.inputName,
        medicineB: b.inputName,
        found: true,
        excerpt: aExcerpt,
        mentionedIn: a.inputName,
      );
    }
    final bExcerpt = _findMention(b.interactionsText, a);
    if (bExcerpt != null) {
      return DrugInteractionResult(
        medicineA: a.inputName,
        medicineB: b.inputName,
        found: true,
        excerpt: bExcerpt,
        mentionedIn: b.inputName,
      );
    }
    return DrugInteractionResult(
      medicineA: a.inputName,
      medicineB: b.inputName,
      found: false,
    );
  }

  /// Looks for [other]'s resolved (or raw) name as a whole word inside
  /// [text], returning the containing sentence if found.
  String? _findMention(String? text, ResolvedMedicine other) {
    if (text == null) return null;
    final needle = (other.matchedName ?? other.inputName).toLowerCase();
    if (needle.isEmpty) return null;

    final pattern =
        RegExp(r'\b' + RegExp.escape(needle) + r'\b', caseSensitive: false);
    final match = pattern.firstMatch(text);
    if (match == null) return null;

    // Expand to the containing sentence for readable context.
    final periodBefore = text.lastIndexOf('. ', match.start);
    final sentenceStart = periodBefore == -1 ? 0 : periodBefore + 2;
    final sentenceEndCandidates = ['. ', '.\n'];
    var sentenceEnd = text.length;
    for (final delim in sentenceEndCandidates) {
      final idx = text.indexOf(delim, match.end);
      if (idx != -1 && idx < sentenceEnd) sentenceEnd = idx + 1;
    }
    final excerpt = text.substring(sentenceStart, sentenceEnd).trim();
    return excerpt.length > 400 ? '${excerpt.substring(0, 400)}…' : excerpt;
  }
}

/// Dedicated Dio instance for public third-party health-data APIs
/// (RxNav/openFDA) — deliberately not [dioClientProvider], which attaches
/// the user's Supabase auth token; that token has no business leaving the
/// app's own backend.
final interactionsDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
});

final interactionRepositoryProvider = Provider<InteractionRepository>((ref) {
  return InteractionRepository(ref.watch(interactionsDioProvider));
});
