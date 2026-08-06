import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assistant/data/assistant_service.dart';
import '../../assistant/domain/chat_message.dart';

@immutable
class _NarrationKey {
  const _NarrationKey({
    required this.insightId,
    required this.statement,
    required this.language,
  });

  final String insightId;
  final String statement;
  final AssistantLanguage language;

  @override
  bool operator ==(Object other) =>
      other is _NarrationKey &&
      other.insightId == insightId &&
      other.statement == statement &&
      other.language == language;

  @override
  int get hashCode => Object.hash(insightId, statement, language);
}

/// Caches one narration attempt per (insight, statement, language) — so
/// scrolling the timeline doesn't repeatedly re-call the LLM for the same
/// card, and a different statement (e.g. after data changes) gets its own
/// fresh attempt rather than showing a stale narration.
final _narratedInsightProvider =
    FutureProvider.family<String, _NarrationKey>((ref, key) {
  return ref.watch(assistantServiceProvider).narrate(
        key.statement,
        key.language,
      );
});

/// Renders [fallback] — the deterministic, already-correct text — right
/// away, then silently swaps in a warmer LLM-narrated rephrasing if one
/// comes back before the widget is disposed. Never shows a loading spinner
/// or blocks on the network: [fallback] alone is always a complete and
/// correct thing to show. See [AssistantService.narrate] for the safety
/// reasoning behind why this only ever rephrases, never adds information.
class NarratedInsightText extends ConsumerWidget {
  const NarratedInsightText({
    super.key,
    required this.insightId,
    required this.fallback,
    this.style,
  });

  final String insightId;
  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = Localizations.localeOf(context).languageCode;
    final language = AssistantLanguage.values.firstWhere(
      (l) => l.code == localeCode,
      orElse: () => AssistantLanguage.english,
    );
    final narrated = ref.watch(
      _narratedInsightProvider(
        _NarrationKey(
          insightId: insightId,
          statement: fallback,
          language: language,
        ),
      ),
    );
    return Text(narrated.valueOrNull ?? fallback, style: style);
  }
}
