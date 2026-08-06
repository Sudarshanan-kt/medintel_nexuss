import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/dio_client.dart';
import '../domain/chat_message.dart';

/// Talks to the underlying LLM.
///
/// Resolution order for the API key:
///   1. Runtime override saved to secure storage via the in-app settings.
///   2. `--dart-define=GROQ_API_KEY=...` build flag.
///   3. None — fall back to the curated demo response set.
///
/// Provider: Groq (Llama 3.3 70B). Free tier, sub-second responses, native
/// Tamil & Hindi quality. Get a key at console.groq.com/keys.
class AssistantService {
  AssistantService({required this.dio, required this.storage});

  final Dio dio;
  final FlutterSecureStorage storage;

  static const String _kGroqApiKey = 'mn_groq_api_key';
  static const String _envKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: '');
  static const String _endpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';

  Future<String?> getApiKey() async {
    final stored = await storage.read(key: _kGroqApiKey);
    if (stored != null && stored.isNotEmpty) return stored;
    if (_envKey.isNotEmpty) return _envKey;
    return null;
  }

  Future<void> setApiKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await storage.delete(key: _kGroqApiKey);
    } else {
      await storage.write(key: _kGroqApiKey, value: key.trim());
    }
  }

  Future<bool> hasApiKey() async => (await getApiKey()) != null;

  /// Generate an assistant reply for [prompt]. Honours conversation history
  /// and the active language.
  Future<String> reply({
    required String prompt,
    required List<ChatMessage> history,
    required AssistantLanguage language,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) return _fallback(prompt, language);

    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': _systemPrompt(language)},
        for (final m in history.take(10))
          {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.content,
          },
        {'role': 'user', 'content': prompt},
      ];

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
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 350,
        }),
      );

      final json = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) return _fallback(prompt, language);
      final msg = (choices.first as Map)['message'] as Map?;
      final content = msg?['content'] as String?;
      return content?.trim().isNotEmpty == true
          ? content!.trim()
          : _fallback(prompt, language);
    } on DioException catch (e) {
      debugPrint('Groq request failed: ${e.message}');
      return _fallback(prompt, language);
    } catch (e) {
      debugPrint('Groq parse failed: $e');
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
    final apiKey = await getApiKey();
    if (apiKey == null) return statement;

    try {
      final res = await dio.post<String>(
        _endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
        data: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _narratorSystemPrompt(language)},
            {'role': 'user', 'content': statement},
          ],
          'temperature': 0.3,
          'max_tokens': 120,
        }),
      );

      final json = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) return statement;
      final msg = (choices.first as Map)['message'] as Map?;
      final content = (msg?['content'] as String?)?.trim();
      return content?.isNotEmpty == true ? content! : statement;
    } catch (e) {
      debugPrint('Groq narrate failed: $e');
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
    final apiKey = await getApiKey();
    if (apiKey == null) return null;

    try {
      final res = await dio.post<String>(
        _endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
        data: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _triageSystemPrompt(language)},
            {
              'role': 'user',
              'content': transcript.isEmpty
                  ? 'Begin the triage. Ask your first question.'
                  : transcript,
            },
          ],
          'temperature': 0.2,
          'max_tokens': 300,
          'response_format': {'type': 'json_object'},
        }),
      );

      final json = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final choices = (json['choices'] as List?) ?? const [];
      if (choices.isEmpty) return null;
      final msg = (choices.first as Map)['message'] as Map?;
      final content = (msg?['content'] as String?)?.trim();
      if (content == null || content.isEmpty) return null;
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('Groq triageStep failed: $e');
      return null;
    }
  }

  String _triageSystemPrompt(AssistantLanguage lang) {
    const base = '''
You run a short, adaptive symptom-triage questionnaire for a patient. You
are NOT a doctor and must NEVER name a specific diagnosis or condition —
only assess urgency and point to the right next step. Reply with ONLY one
strict JSON object, nothing else — no markdown, no backticks, no text
outside the JSON.

Shape 1 — to ask a follow-up question (use short, plain language):
{"type":"question","question":"<one short question>","options":["<opt1>","<opt2>","<opt3>"]}
"options" must have between 2 and 5 short, tappable choices — never leave
it empty, never expect free-text input.

Shape 2 — to conclude the triage (do this within 5 questions total, sooner
if you already have enough information):
{"type":"result","urgency":"self_care","summary":"<1-2 sentences, no diagnosis, just what to do next>"}
"urgency" must be exactly one of: "self_care", "see_doctor", "urgent", "emergency".

Rules:
- If at any point the description includes chest pain, severe or
  uncontrolled bleeding, difficulty breathing, stroke symptoms (face
  drooping, slurred speech, one-sided weakness), suicidal thoughts, or
  a severe allergic reaction, immediately return a result with urgency
  "emergency" — do not ask further questions.
- Never state or imply what condition the patient has. Only urgency and
  next-step guidance.
- Ask exactly one question per turn.
''';
    return switch (lang) {
      AssistantLanguage.english =>
        '$base\nWrite all question/option/summary text in natural English.',
      AssistantLanguage.tamil =>
        '$base\nWrite all question/option/summary text in spoken, everyday Tamil (தமிழ்). Keep the JSON keys and urgency values in English exactly as specified.',
      AssistantLanguage.hindi =>
        '$base\nWrite all question/option/summary text in spoken, everyday Hindi (हिन्दी). Keep the JSON keys and urgency values in English exactly as specified.',
    };
  }

  String _narratorSystemPrompt(AssistantLanguage lang) {
    const base = '''
You rephrase a single already-verified factual health statement into 1-2
warm, natural, conversational sentences for a patient to read. You do NOT
add any new fact, number, medicine name, or claim that isn't already in the
input. You do NOT diagnose or give new advice beyond what's stated. Every
number, medicine name, and measurement in the input must appear unchanged
in your output. If you cannot rephrase it faithfully, repeat it verbatim.
Reply with only the rephrased sentence — no preamble, no quotes.
''';
    return switch (lang) {
      AssistantLanguage.english => '$base\nRespond in natural English.',
      AssistantLanguage.tamil =>
        '$base\nRespond in spoken, everyday Tamil (தமிழ்).',
      AssistantLanguage.hindi =>
        '$base\nRespond in spoken, everyday Hindi (हिन्दी).',
    };
  }

  String _systemPrompt(AssistantLanguage lang) {
    const base = '''
You are MedIntel Nexus's clinical assistant — calm, warm, conversational and
human. You talk to the patient like a thoughtful friend who happens to know
medicine. Avoid robotic language. Vary your sentence structure. You may use
contractions. Address the patient by first name (Aravind) occasionally.

You help with: medicines, prescriptions, lab reports, risk flags, dosage
schedules, adherence, side effects, drug interactions, and general health
questions. Keep replies short by default (2-4 sentences) but go deeper if
the user asks. Never invent specific lab values, dosages, or prescriptions
you weren't told about; if you don't have the data, say so honestly.

You are not a doctor. For diagnosis, dosing changes, severe symptoms, or
emergencies, point the user to their clinician. If the user describes chest
pain, suicidal thoughts, severe bleeding, stroke symptoms, anaphylaxis or
similar emergencies, urge them to call emergency services immediately.
''';
    return switch (lang) {
      AssistantLanguage.english =>
        '$base\nRespond in natural, conversational English.',
      AssistantLanguage.tamil =>
        '$base\nRespond in spoken Tamil (தமிழ்) — the warm, everyday register people actually use, not literary Tamil. Mix in occasional English words only where natural (medicine names, units).',
      AssistantLanguage.hindi =>
        '$base\nRespond in spoken Hindi (हिन्दी) — the warm, everyday register, not formal Hindi.',
    };
  }

  String _fallback(String prompt, AssistantLanguage lang) {
    final p = prompt.toLowerCase().trim();

    String pick(List<String> en, List<String> ta, List<String> hi) {
      final list = switch (lang) {
        AssistantLanguage.english => en,
        AssistantLanguage.tamil => ta,
        AssistantLanguage.hindi => hi,
      };
      return list[DateTime.now().millisecondsSinceEpoch % list.length];
    }

    if (RegExp(r'\b(hi|hello|hey|namaste|vanakkam|வணக்கம்|नमस्ते)\b')
        .hasMatch(p)) {
      return pick(
        [
          "Hi Aravind. What's on your mind today?",
          "Hey — anything you'd like me to look up about your prescriptions?",
        ],
        [
          'வணக்கம் அரவிந்த். இன்று என்ன கேக்கணும்?',
          'ஹாய், என்ன உதவி வேண்டும்?',
        ],
        ['नमस्ते अरविंद, क्या मदद चाहिए?'],
      );
    }

    if (p.contains('ibuprofen') ||
        p.contains('warfarin') ||
        p.contains('interaction')) {
      return pick(
        [
          "Ibuprofen with Warfarin can bump up bleeding risk — that's why I'd lean towards paracetamol for pain. But please run any switch by your doctor first.",
        ],
        [
          'வார்ஃபரின் உடன் ஐபுப்ரோஃபன் சேர்த்தா ரத்தப்போக்கு ரிஸ்க் கூடிடும். வலி இருக்கா? பாராசிட்டமால் சேஃபா இருக்கும். ஆனா மாற்றுவதுக்கு முன்னாடி டாக்டரிடம் கேக்கணும்.',
        ],
        [
          'वारफरिन के साथ इबुप्रोफेन से ब्लीडिंग बढ़ सकती है। दर्द हो तो पैरासिटामॉल बेहतर — पर बदलाव से पहले डॉक्टर से पूछो।',
        ],
      );
    }

    if (p.contains('adherence') || p.contains('missed') || p.contains('dose')) {
      return pick(
        [
          'Check the Reminders tab for your real adherence streak and weekly percentage. If you miss a dose, take it as soon as you remember, unless the next dose is close — never double up.',
        ],
        [
          'உங்க உண்மையான டோஸ் கடைப்பிடிப்பு streak & வார சதவீதத்தை Reminders tab-ல பாருங்க. ஒரு டோஸ் தவறிட்டா, அடுத்த நேரம் வெகுதூரம் இல்லைன்னா உடனே எடுத்துக்கங்க. டபுள் வேண்டாம்.',
        ],
        [
          'अपनी असली adherence streak और साप्ताहिक प्रतिशत के लिए Reminders टैब देखें। खुराक छूट गई तो जल्दी ले लो, पर अगली खुराक नज़दीक हो तो डबल मत करना।',
        ],
      );
    }

    return pick(
      [
        "I hear you. To answer properly I'd want to look at your latest scan or report — want me to pull that up?",
        "Tell me a bit more — is this about a medicine you've been prescribed, a lab value, or something you're feeling right now?",
      ],
      [
        'புரியுது. சரியான பதில் சொல்ல சமீபத்திய ஸ்கேன் அல்லது அறிக்கையை பார்க்கணும். எடுக்கட்டுமா?',
        'கொஞ்சம் மேலே சொல்லுங்க — மருந்து பத்தியா, ஆய்வக மதிப்பு பத்தியா, அல்லது இப்போ உடம்பு எப்படி இருக்கு?',
      ],
      ['समझ गया, थोड़ी और बात बताओ — दवा, रिपोर्ट या तबियत?'],
    );
  }
}

final assistantServiceProvider = Provider<AssistantService>((ref) {
  return AssistantService(
    dio: Dio(),
    storage: ref.watch(secureStorageProvider),
  );
});
