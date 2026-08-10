import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../domain/chat_message.dart';
import 'on_device_llm.dart';

/// Talks to the assistant, via the backend.
///
/// Inference runs on a model hosted on the backend machine (Ollama by
/// default), not a cloud provider — so no API key ships inside the app, and
/// a patient's health conversation never leaves the deployment. The system
/// prompts live server-side with it, in `app/routers/assistant.py`.
///
/// Every method degrades to the curated fallback copy below when the model
/// isn't reachable. That copy is deliberately kept here rather than on the
/// server: it's UI text in three languages, not model output, and the app
/// has to stay usable with the backend switched off entirely.
class AssistantService {
  AssistantService({required this.dio, required this.onDevice});

  final Dio dio;
  final OnDeviceLlm onDevice;

  /// Whether a model is available to answer, on the phone or on the backend.
  ///
  /// On-device is checked first because it's the path that works without a
  /// server, a network or the right Wi-Fi.
  Future<bool> isModelAvailable() async {
    if (await OnDeviceLlm.isInstalled() && await onDevice.ensureLoaded()) {
      return true;
    }
    try {
      final res = await dio.get<Map<String, dynamic>>(
        ApiEndpoints.llmHealth,
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      return res.data?['status'] == 'ok';
    } catch (e) {
      debugPrint('Backend model health check failed: $e');
      return false;
    }
  }

  /// True when replies are being generated on the phone rather than served
  /// by the backend. Surfaced so the UI can say which is answering.
  Future<bool> isRunningOnDevice() async =>
      await OnDeviceLlm.isInstalled() && onDevice.isReady;

  /// The system prompt used for on-device generation.
  ///
  /// The backend keeps its own copy for the server path. They're deliberately
  /// close but not shared: this one is terser because a 1.5B model follows
  /// short, concrete instructions far better than long ones.
  String _systemPrompt(AssistantLanguage language) {
    const base = '''
You are MedIntel Nexus's clinical assistant. You are warm, calm and brief —
2 to 4 sentences unless asked for more.

You help with medicines, prescriptions, lab reports, dosage schedules,
adherence and side effects. Never invent a lab value, dosage or prescription
you weren't told about; if you don't have the data, say so.

You are not a doctor. Point anything involving diagnosis or a dosing change
to the patient's clinician. If chest pain, severe bleeding, trouble
breathing, stroke signs or suicidal thoughts are mentioned, tell them to
call emergency services now.''';

    return switch (language) {
      AssistantLanguage.english => '$base\nReply in English.',
      AssistantLanguage.tamil =>
        '$base\nReply in everyday spoken Tamil (தமிழ்).',
      AssistantLanguage.hindi =>
        '$base\nReply in everyday spoken Hindi (हिन्दी).',
    };
  }

  /// Unwraps the standard `{data, error}` success envelope.
  Map<String, dynamic> _data(Response<Map<String, dynamic>> res) {
    final data = res.data?['data'];
    return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
  }

  List<({bool isUser, String text})> _historyFor(List<ChatMessage> history) => [
        for (final m in history.take(10)) (isUser: m.isUser, text: m.content),
      ];

  /// Streams a reply from the on-device model, token by token.
  ///
  /// Returns null when there's no on-device model to stream from, so the
  /// caller can fall back to the whole-answer path rather than showing an
  /// empty bubble. Streaming exists purely for how it feels: the total
  /// generation time is the same, but the first words land in well under a
  /// second instead of after the entire answer is ready.
  Stream<String>? replyStream({
    required String prompt,
    required List<ChatMessage> history,
    required AssistantLanguage language,
  }) {
    if (!onDevice.isReady) return null;
    return onDevice.generateStream(
      systemPrompt: _systemPrompt(language),
      language: language,
      history: _historyFor(history),
      prompt: prompt,
    );
  }

  /// Generate an assistant reply for [prompt]. Honours conversation history
  /// and the active language.
  Future<String> reply({
    required String prompt,
    required List<ChatMessage> history,
    required AssistantLanguage language,
  }) async {
    // 1 · The phone's own model, when it's installed. No server, no
    // network, and nothing about the patient's health leaves the handset.
    if (await OnDeviceLlm.isInstalled()) {
      final local = await onDevice.generate(
        systemPrompt: _systemPrompt(language),
        language: language,
        history: _historyFor(history),
        prompt: prompt,
      );
      if (local != null) return local;
      // Fall through — a model that's installed but failed to load or
      // answer shouldn't take the assistant down with it.
    }

    // 2 · The backend, which runs a larger model when it's reachable.
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.assistantMessages,
        options: Options(
          // A local model is slower than a hosted one — a 7B on CPU can take
          // the better part of a minute for a long reply.
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 15),
        ),
        data: {
          'prompt': prompt,
          'language': language.code,
          'history': [
            for (final m in history.take(10))
              {'role': m.isUser ? 'user' : 'assistant', 'content': m.content},
          ],
        },
      );

      final data = _data(res);
      // `generated: false` means the model couldn't be reached — an empty
      // bubble would look like the assistant ignoring the patient.
      if (data['generated'] != true) return _fallback(prompt, language);
      final content = (data['content'] as String?)?.trim();
      return (content == null || content.isEmpty)
          ? _fallback(prompt, language)
          : content;
    } on DioException catch (e) {
      debugPrint('Assistant request failed: ${e.message}');
      return _fallback(prompt, language);
    } catch (e) {
      debugPrint('Assistant parse failed: $e');
      return _fallback(prompt, language);
    }
  }

  /// Rephrases an already-computed, already-verified factual [statement]
  /// into 1-2 warmer, more natural sentences — used by the health
  /// timeline's [CorrelationEngine] insights.
  ///
  /// Deliberately narrow: this must never be asked to *decide* anything or
  /// add information, only restate what it's given, because a hallucinated
  /// addition to a health correlation is a safety risk, not a style
  /// choice. If the model can't be reached, isn't configured, or its
  /// response can't be trusted to be a faithful rephrasing, [statement] is
  /// returned unchanged — the deterministic text is always a complete,
  /// correct answer on its own; this only ever makes it read better.
  Future<String> narrate(String statement, AssistantLanguage language) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.assistantNarrate,
        options: Options(
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 8),
        ),
        data: {'statement': statement, 'language': language.code},
      );

      final data = _data(res);
      if (data['rephrased'] != true) return statement;
      final text = (data['text'] as String?)?.trim();
      return (text == null || text.isEmpty) ? statement : text;
    } catch (e) {
      debugPrint('Assistant narrate failed: $e');
      return statement;
    }
  }

  /// One step of the structured symptom-triage flow (see
  /// `lib/features/triage/`). [transcript] is the plain-text record of
  /// every question asked and answer chosen so far ("" for the first
  /// call). Returns the raw JSON object the model replied with, or null
  /// if it couldn't be reached or its reply didn't parse as JSON at all —
  /// callers must still independently validate the shape, this method only
  /// guarantees *some* JSON object came back, not that it's a valid turn.
  ///
  /// Deliberately separate from [reply]: triage output drives a UI flow
  /// (urgency banners, next questions), so an unstructured free-text
  /// response is useless here, unlike the open chat.
  Future<Map<String, dynamic>?> triageStep({
    required String transcript,
    required AssistantLanguage language,
  }) async {
    try {
      final res = await dio.post<Map<String, dynamic>>(
        ApiEndpoints.assistantTriage,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 10),
        ),
        data: {'transcript': transcript, 'language': language.code},
      );

      final step = _data(res)['step'];
      return step is Map ? step.cast<String, dynamic>() : null;
    } catch (e) {
      debugPrint('Assistant triageStep failed: $e');
      return null;
    }
  }

  /// What the assistant says when no model answered.
  ///
  /// This used to return canned replies — including invented drug advice
  /// ("Ibuprofen with Warfarin can bump up bleeding risk… I'd lean towards
  /// paracetamol") and a greeting addressed to a hardcoded name. A patient
  /// cannot tell a fabricated answer from a real one, and an assistant that
  /// invents clinical guidance whenever the model is unreachable is worse
  /// than one that admits it is unreachable.
  ///
  /// So it says nothing about the question. The caller is offline, and that
  /// is the only fact available.
  String _fallback(String prompt, AssistantLanguage lang) => switch (lang) {
        AssistantLanguage.english =>
          "I can't reach the assistant right now, so I won't guess at an "
              'answer. Check that the model is running, then ask me again.',
        AssistantLanguage.tamil =>
          'இப்போது உதவியாளரை அணுக முடியவில்லை. ஊகித்து பதில் சொல்ல '
              'விரும்பவில்லை. மாடல் இயங்குகிறதா என பார்த்துவிட்டு மீண்டும் கேளுங்கள்.',
        AssistantLanguage.hindi =>
          'अभी असिस्टेंट से संपर्क नहीं हो पा रहा, इसलिए मैं अंदाज़े से जवाब '
              'नहीं दूँगा। मॉडल चल रहा है या नहीं देखकर दोबारा पूछें।',
      };
}

final assistantServiceProvider = Provider<AssistantService>((ref) {
  return AssistantService(
    dio: ref.watch(dioClientProvider),
    onDevice: ref.watch(onDeviceLlmProvider),
  );
});
