import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../domain/drug_interaction_result.dart';

/// Checks medicine combinations against the backend's interaction database.
///
/// This used to assemble an answer client-side from two public APIs —
/// RxNorm to resolve names, then openFDA's label text searched for a mention
/// of the other drug. That was replaced for three reasons:
///
///  1. It sent the patient's medicine list to third-party servers on every
///     check. Nothing about a person's prescription needs to leave the
///     deployment.
///  2. It was a text search, not a graded verdict: a "no mention found"
///     result and a genuine all-clear were indistinguishable, and an
///     interaction phrased around a drug class rather than an ingredient
///     name was invisible to it.
///  3. Two network round-trips per drug plus a pairwise scan, versus one
///     call to a local table.
///
/// The backend answers from DDInter 2.0, so the same combination always
/// gives the same verdict and that verdict cites a source.
class InteractionRepository {
  InteractionRepository(this._dio);

  final Dio _dio;

  /// Checks every pair among [medicineNames].
  ///
  /// Never throws: a failure returns a result with `checked: false`, because
  /// an exception surfaced as an error state is easy to misread as "nothing
  /// found" once it's been retried away.
  Future<InteractionCheck> checkInteractions(List<String> medicineNames) async {
    final unique = medicineNames
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    if (unique.length < 2) {
      return const InteractionCheck(
        checked: true,
        interactions: [],
        overallRisk: RiskLevel.none,
        disclaimer: 'Add at least two medicines to check for interactions.',
      );
    }

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.interactionsCheck,
        options: Options(
          // The backend may generate a plain-language explanation per
          // interacting pair on a local model, which is not fast.
          receiveTimeout: const Duration(seconds: 120),
        ),
        data: {'medicine_names': unique},
      );

      final data = res.data?['data'];
      if (data is! Map) return _unavailable();
      return _parse(data.cast<String, dynamic>());
    } catch (_) {
      return _unavailable();
    }
  }

  InteractionCheck _parse(Map<String, dynamic> data) {
    if (data['checked'] != true) return _unavailable();

    return InteractionCheck(
      checked: true,
      overallRisk: _risk(data['overall_risk'] as String?),
      interactions: [
        for (final raw in (data['interactions'] as List? ?? const []))
          if (raw is Map) _interaction(raw.cast<String, dynamic>()),
      ],
      unrecognized: [
        for (final n in (data['unrecognized'] as List? ?? const []))
          n.toString(),
      ],
      ungradedPairCount: (data['ungraded_pair_count'] as num?)?.toInt() ?? 0,
      disclaimer: (data['disclaimer'] as String?) ?? '',
      source: data['source'] as String?,
    );
  }

  DrugInteraction _interaction(Map<String, dynamic> raw) {
    final names = (raw['medicines'] as List? ?? const [])
        .map((n) => n.toString())
        .toList();
    return DrugInteraction(
      medicineA: names.isNotEmpty ? names[0] : '—',
      medicineB: names.length > 1 ? names[1] : '—',
      risk: _risk(raw['risk'] as String?) ?? RiskLevel.moderate,
      level: (raw['level'] as String?) ?? 'Moderate',
      mechanism: (raw['mechanism'] as String?)?.trim() ?? '',
      recommendation: (raw['recommendation'] as String?)?.trim() ?? '',
      explained: raw['explained'] != false,
    );
  }

  RiskLevel? _risk(String? value) => switch (value) {
        'severe' => RiskLevel.severe,
        'moderate' => RiskLevel.moderate,
        'none' => RiskLevel.none,
        _ => null,
      };

  InteractionCheck _unavailable() => const InteractionCheck(
        checked: false,
        interactions: [],
        // Deliberately null, not none: the check did not run, so there is no
        // verdict to report.
        overallRisk: null,
        disclaimer: 'Interaction check unavailable right now — please consult '
            'a pharmacist or doctor before combining these medicines.',
      );
}

final interactionRepositoryProvider = Provider<InteractionRepository>((ref) {
  return InteractionRepository(ref.watch(dioClientProvider));
});
