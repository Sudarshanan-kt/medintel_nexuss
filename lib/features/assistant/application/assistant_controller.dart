import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/assistant_service.dart';
import '../data/voice_service.dart';
import '../domain/chat_message.dart';
import '../domain/voice_state.dart';

class AssistantState {
  const AssistantState({
    required this.messages,
    required this.language,
    this.phase = VoicePhase.idle,
    this.liveTranscript = '',
    this.amplitude = 0,
    this.errorMessage,
    this.handsFree = false,
  });

  final List<ChatMessage> messages;
  final AssistantLanguage language;
  final VoicePhase phase;

  /// Live partial transcript shown while the user is speaking.
  final String liveTranscript;

  /// Mic amplitude 0..1 while listening. Drives the waveform animation.
  final double amplitude;

  final String? errorMessage;

  /// When true, the assistant automatically re-opens the microphone after
  /// speaking each reply — a continuous back-and-forth conversation with no
  /// tap needed between turns. Exits itself (see [AssistantController]) if a
  /// listening turn times out with no speech, so the mic never stays hot
  /// indefinitely without the user actively talking.
  final bool handsFree;

  AssistantState copyWith({
    List<ChatMessage>? messages,
    AssistantLanguage? language,
    VoicePhase? phase,
    String? liveTranscript,
    double? amplitude,
    String? errorMessage,
    bool? handsFree,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      language: language ?? this.language,
      phase: phase ?? this.phase,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      amplitude: amplitude ?? this.amplitude,
      errorMessage: errorMessage,
      handsFree: handsFree ?? this.handsFree,
    );
  }

  ChatMessage? get lastAssistantMessage {
    for (final m in messages.reversed) {
      if (!m.isUser) return m;
    }
    return null;
  }

  ChatMessage? get lastUserMessage {
    for (final m in messages.reversed) {
      if (m.isUser) return m;
    }
    return null;
  }
}

class AssistantController extends Notifier<AssistantState> {
  late final VoiceService _voice = ref.read(voiceServiceProvider);
  late final AssistantService _service = ref.read(assistantServiceProvider);

  @override
  AssistantState build() {
    // Best-effort: warm up the voice subsystems on first access.
    Future.microtask(_voice.initialise);
    return const AssistantState(
      language: AssistantLanguage.english,
      messages: [
        ChatMessage(
          id: 'welcome',
          role: MessageRole.assistant,
          content:
              "Hi Aravind. I'm your MedIntel assistant. Tap and hold to talk — ask me about your medicines, reports, or how to take a dose. I'm here in English or Tamil.",
          language: AssistantLanguage.english,
        ),
      ],
    );
  }

  void setLanguage(AssistantLanguage lang) {
    state = state.copyWith(language: lang, errorMessage: null);
  }

  /// Turns hands-free conversation mode on/off. Turning it on immediately
  /// opens the mic (if idle); turning it off behaves like [interrupt].
  Future<void> toggleHandsFree() async {
    if (state.handsFree) {
      await interrupt();
      return;
    }
    state = state.copyWith(handsFree: true);
    if (state.phase == VoicePhase.idle) await startListening();
  }

  /// Begin a voice turn — open the microphone, stream partials, on final
  /// submit the transcript to the LLM, then speak the answer aloud.
  Future<void> startListening() async {
    if (state.phase == VoicePhase.listening) return;
    await _voice.stopSpeaking();

    state = state.copyWith(
      phase: VoicePhase.listening,
      liveTranscript: '',
      errorMessage: null,
    );

    final opened = await _voice.listen(
      language: state.language,
      onPartial: (t) {
        if (state.phase != VoicePhase.listening) return;
        state = state.copyWith(liveTranscript: t);
      },
      onAmplitude: (a) {
        if (state.phase != VoicePhase.listening) return;
        state = state.copyWith(amplitude: a);
      },
      onFinal: (t) async {
        final clean = t.trim();
        if (clean.isEmpty) {
          // Silence timeout — don't leave the mic hot indefinitely; drop
          // out of hands-free mode too, so it never listens unattended.
          state = state.copyWith(
            phase: VoicePhase.idle,
            liveTranscript: '',
            amplitude: 0,
            handsFree: false,
          );
          return;
        }
        await _processTurn(clean);
      },
    );

    // The microphone never opened. Say so and stand down — leaving the
    // phase on `listening` is what made this look like the assistant was
    // ignoring the user.
    if (!opened) {
      state = state.copyWith(
        phase: VoicePhase.error,
        liveTranscript: '',
        amplitude: 0,
        handsFree: false,
        errorMessage: _voice.unavailableReason ??
            'Could not start listening. You can type instead.',
      );
    }
  }

  /// Stop a listening turn early (button released). Submits the partial
  /// transcript if there is one.
  Future<void> stopListening() async {
    final partial = state.liveTranscript.trim();
    await _voice.stopListening();
    if (state.phase != VoicePhase.listening) return;
    if (partial.isEmpty) {
      state = state.copyWith(phase: VoicePhase.idle, liveTranscript: '');
      return;
    }
    await _processTurn(partial);
  }

  Future<void> _processTurn(String userText) async {
    final lang = state.language;
    final userMsg = ChatMessage(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.user,
      content: userText,
      language: lang,
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg],
      phase: VoicePhase.thinking,
      liveTranscript: '',
    );

    try {
      final history = state.messages;
      String reply;

      // Stream from the on-device model when it's the one answering, so the
      // reply starts appearing immediately rather than after the whole
      // answer is generated. The wait is the same; the blank screen isn't.
      final stream = _service.replyStream(
        prompt: userText,
        history: history,
        language: lang,
      );

      if (stream != null) {
        final messageId = 'a_${DateTime.now().microsecondsSinceEpoch}';
        final buffer = StringBuffer();
        var placed = false;

        await for (final token in stream) {
          buffer.write(token);
          final partial = ChatMessage(
            id: messageId,
            role: MessageRole.assistant,
            content: buffer.toString(),
            language: lang,
          );
          state = state.copyWith(
            // First token replaces the thinking state; later ones swap the
            // message in place rather than appending a new bubble.
            messages: placed
                ? [...state.messages.sublist(0, state.messages.length - 1), partial]
                : [...state.messages, partial],
            phase: VoicePhase.speaking,
          );
          placed = true;
        }
        reply = buffer.toString().trim();

        // The stream produced nothing — fall back to the whole-answer path
        // rather than leaving an empty bubble.
        if (reply.isEmpty) {
          if (placed) {
            state = state.copyWith(
              messages: state.messages.sublist(0, state.messages.length - 1),
            );
          }
          reply = await _service.reply(
            prompt: userText,
            history: history,
            language: lang,
          );
          state = state.copyWith(
            messages: [
              ...state.messages,
              ChatMessage(
                id: messageId,
                role: MessageRole.assistant,
                content: reply,
                language: lang,
              ),
            ],
            phase: VoicePhase.speaking,
          );
        }
      } else {
        reply = await _service.reply(
          prompt: userText,
          history: history,
          language: lang,
        );
        state = state.copyWith(
          messages: [
            ...state.messages,
            ChatMessage(
              id: 'a_${DateTime.now().microsecondsSinceEpoch}',
              role: MessageRole.assistant,
              content: reply,
              language: lang,
            ),
          ],
          phase: VoicePhase.speaking,
        );
      }

      await _voice.speak(reply, lang);
      if (state.phase == VoicePhase.speaking) {
        state = state.copyWith(phase: VoicePhase.idle);
        // Hands-free: keep the conversation going with no tap required.
        if (state.handsFree) await startListening();
      }
    } catch (e) {
      state = state.copyWith(
        phase: VoicePhase.error,
        errorMessage: 'Could not reach the assistant. Try again.',
      );
    }
  }

  /// Send a typed message (fallback when the user prefers keyboard).
  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    await _voice.stopSpeaking();
    await _processTurn(text.trim());
  }

  Future<void> interrupt() async {
    await _voice.stopSpeaking();
    await _voice.stopListening();
    state = state.copyWith(
      phase: VoicePhase.idle,
      liveTranscript: '',
      handsFree: false,
    );
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantState>(
  AssistantController.new,
);
