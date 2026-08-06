import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../assistant/data/assistant_service.dart';
import '../../assistant/domain/chat_message.dart';
import '../domain/triage_models.dart';

/// Hard cap on questions asked, independent of what the model does —
/// guarantees the flow always terminates even if the LLM never emits a
/// "result" turn.
const int _maxQuestions = 5;

class TriageState {
  const TriageState({
    this.history = const [],
    this.current,
    this.loading = true,
    this.error = false,
  });

  final List<TriageQaTurn> history;

  /// The turn currently shown to the user — a question to answer, or the
  /// final result. Null only during the very first load.
  final TriageTurn? current;

  final bool loading;

  /// True when the LLM couldn't be reached/parsed and [current] is the
  /// safe fallback result rather than a real assessment.
  final bool error;

  TriageState copyWith({
    List<TriageQaTurn>? history,
    TriageTurn? current,
    bool? loading,
    bool? error,
  }) =>
      TriageState(
        history: history ?? this.history,
        current: current ?? this.current,
        loading: loading ?? this.loading,
        error: error ?? this.error,
      );
}

/// Drives the adaptive symptom-triage questionnaire (see
/// `AssistantService.triageStep`). Never diagnoses — only narrows to an
/// urgency level and next-step guidance, and always terminates within
/// [_maxQuestions] turns even if the model misbehaves.
class TriageController extends AutoDisposeNotifier<TriageState> {
  AssistantService get _service => ref.read(assistantServiceProvider);

  @override
  TriageState build() {
    Future.microtask(_requestNextTurn);
    return const TriageState();
  }

  static const _fallbackResult = TriageResult(
    urgency: TriageUrgency.seeDoctor,
    summary: "We couldn't complete an assessment right now. If anything feels "
        'seriously wrong, please contact a doctor or emergency services — '
        "otherwise it's still worth a check-up when you can.",
  );

  String _buildTranscript() {
    if (history.isEmpty) return '';
    final buf = StringBuffer();
    for (final turn in history) {
      buf.writeln('Q: ${turn.question}');
      buf.writeln('A: ${turn.answer}');
    }
    return buf.toString();
  }

  List<TriageQaTurn> get history => state.history;

  Future<void> _requestNextTurn() async {
    state = state.copyWith(loading: true);

    if (state.history.length >= _maxQuestions) {
      state = state.copyWith(
        current: _fallbackResult,
        loading: false,
        error: false,
      );
      return;
    }

    final raw = await _service.triageStep(
      transcript: _buildTranscript(),
      language: AssistantLanguage.english,
    );
    final turn = parseTriageTurn(raw);

    if (turn == null) {
      state =
          state.copyWith(current: _fallbackResult, loading: false, error: true);
      return;
    }

    state = state.copyWith(current: turn, loading: false, error: false);
  }

  /// Records the chosen option for the current question and requests the
  /// next turn. No-op if [current] isn't a question (e.g. already at the
  /// result screen).
  Future<void> answer(String option) async {
    final current = state.current;
    if (current is! TriageQuestion) return;

    state = state.copyWith(
      history: [
        ...state.history,
        TriageQaTurn(question: current.question, answer: option),
      ],
    );
    await _requestNextTurn();
  }

  /// Starts over from the first question.
  void restart() {
    state = const TriageState();
    Future.microtask(_requestNextTurn);
  }
}

final triageControllerProvider =
    NotifierProvider.autoDispose<TriageController, TriageState>(
  TriageController.new,
);
