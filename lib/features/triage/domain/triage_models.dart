import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// How urgently the patient should seek care — never a diagnosis, only a
/// next step. Matches the exact strings the LLM is instructed to reply
/// with (see `AssistantService._triageSystemPrompt`).
enum TriageUrgency {
  selfCare('self_care', 'Self-care', AppColors.success),
  seeDoctor('see_doctor', 'See a doctor', AppColors.warning),
  // Between "warning" and "danger" — no existing design-token sits here, and
  // this is the only place urgency needs a fourth distinct step.
  urgent('urgent', 'Seek care soon', Color(0xFFF97316)),
  emergency('emergency', 'Emergency — call now', AppColors.danger);

  const TriageUrgency(this.wireValue, this.label, this.color);

  final String wireValue;
  final String label;
  final Color color;

  static TriageUrgency? fromWire(String? value) {
    for (final u in TriageUrgency.values) {
      if (u.wireValue == value) return u;
    }
    return null;
  }
}

/// A single turn in the flow — either a question with fixed options
/// (nothing else is ever shown to the user), or a terminal result.
sealed class TriageTurn {
  const TriageTurn();
}

class TriageQuestion extends TriageTurn {
  const TriageQuestion({required this.question, required this.options});
  final String question;
  final List<String> options;
}

class TriageResult extends TriageTurn {
  const TriageResult({required this.urgency, required this.summary});
  final TriageUrgency urgency;
  final String summary;
}

/// One answered question, kept so the next request can be given the full
/// conversation so far as plain text.
class TriageQaTurn {
  const TriageQaTurn({required this.question, required this.answer});
  final String question;
  final String answer;
}

/// Parses and validates one raw JSON turn from
/// [AssistantService.triageStep]. Returns null for anything that doesn't
/// match one of the two exact expected shapes — an unvalidated reply is
/// never shown to the user; the controller treats null the same as a
/// network failure and falls back to a safe default result.
TriageTurn? parseTriageTurn(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final type = raw['type'] as String?;

  if (type == 'question') {
    final question = raw['question'] as String?;
    final options = raw['options'];
    if (question == null || question.trim().isEmpty) return null;
    if (options is! List || options.length < 2 || options.length > 5) {
      return null;
    }
    final opts =
        options.whereType<String>().where((o) => o.trim().isNotEmpty).toList();
    if (opts.length != options.length) return null;
    return TriageQuestion(question: question.trim(), options: opts);
  }

  if (type == 'result') {
    final urgency = TriageUrgency.fromWire(raw['urgency'] as String?);
    final summary = raw['summary'] as String?;
    if (urgency == null || summary == null || summary.trim().isEmpty) {
      return null;
    }
    return TriageResult(urgency: urgency, summary: summary.trim());
  }

  return null;
}
