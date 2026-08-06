import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/chat_message.dart';

/// Wraps native speech-to-text and text-to-speech behind a single async API.
///
/// On Android we explicitly select Google's TTS engine (the device default
/// on Samsung is Samsung TTS, which sounds robotic) and pick the highest
/// quality voice available for the chosen language. This gets us close to
/// "natural" voices for free; ElevenLabs / OpenAI TTS is the premium path
/// for true JARVIS / FRIDAY quality.
class VoiceService {
  VoiceService();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _ttsReady = false;
  AssistantLanguage? _lastLang;

  Future<bool> initialise() async {
    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onError: (e) => debugPrint('STT error: ${e.errorMsg}'),
        onStatus: (s) => debugPrint('STT status: $s'),
      );
    }
    if (!_ttsReady) {
      await _tts.awaitSpeakCompletion(true);
      // Force the Google TTS engine if installed (much better than Samsung's).
      try {
        final engines = (await _tts.getEngines) as List? ?? const [];
        if (engines.contains('com.google.android.tts')) {
          await _tts.setEngine('com.google.android.tts');
        }
      } catch (_) {/* fall back to default engine */}

      // Slightly slower than default + neutral pitch reads as more "human".
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _ttsReady = true;
    }
    return _sttReady && _ttsReady;
  }

  Future<void> listen({
    required AssistantLanguage language,
    required ValueChanged<String> onPartial,
    required ValueChanged<String> onFinal,
    ValueChanged<double>? onAmplitude,
  }) async {
    if (!_sttReady) await initialise();
    if (!_sttReady) return;

    await _stt.listen(
      localeId: _sttLocaleId(language),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      pauseFor: const Duration(seconds: 2),
      listenFor: const Duration(seconds: 30),
      onSoundLevelChange: (level) {
        final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
        onAmplitude?.call(normalised);
      },
      onResult: (SpeechRecognitionResult r) {
        if (r.finalResult) {
          onFinal(r.recognizedWords);
        } else {
          onPartial(r.recognizedWords);
        }
      },
    );
  }

  Future<void> stopListening() async {
    if (_stt.isListening) await _stt.stop();
  }

  Future<void> speak(String text, AssistantLanguage language) async {
    if (!_ttsReady) await initialise();
    if (_lastLang != language) {
      await _selectBestVoice(language);
      _lastLang = language;
    }
    await _tts.setLanguage(_ttsLocaleId(language));
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  void dispose() {
    _stt.cancel();
    _tts.stop();
  }

  // ── Best-voice selection ─────────────────────────────────────────────
  Future<void> _selectBestVoice(AssistantLanguage lang) async {
    try {
      final voicesRaw = await _tts.getVoices;
      if (voicesRaw is! List) return;
      final voices = voicesRaw
          .whereType<Map>()
          .map((v) => v.map((k, val) => MapEntry(k.toString(), val.toString())))
          .toList();

      final locale = _ttsLocaleId(lang);
      final langPrefix = locale.split('-').first; // e.g. 'en', 'ta'

      // Step 1: filter voices matching the locale (e.g. en-IN), or at least
      // the language (en-*) as a fallback.
      final exact =
          voices.where((v) => (v['locale'] ?? '').startsWith(locale)).toList();
      final fallback = voices
          .where((v) => (v['locale'] ?? '').startsWith(langPrefix))
          .toList();
      final pool = exact.isNotEmpty ? exact : fallback;
      if (pool.isEmpty) return;

      // Step 2: rank by quality heuristics — names like "x-*-network" or
      // containing "Neural"/"Wavenet" are the high-quality voices Google
      // TTS provides. Female-toned defaults read as warmer / FRIDAY-like.
      String score(Map<String, String> v) {
        final n = (v['name'] ?? '').toLowerCase();
        var s = 0;
        if (n.contains('network')) s += 100;
        if (n.contains('neural')) s += 100;
        if (n.contains('wavenet')) s += 90;
        if (n.contains('enhanced')) s += 50;
        if (n.contains('female')) s += 10;
        // Prefer ones with shorter names (typically default high quality).
        return '${100 - s},$n';
      }

      pool.sort((a, b) => score(a).compareTo(score(b)));
      final best = pool.first;

      await _tts.setVoice({
        'name': best['name'] ?? '',
        'locale': best['locale'] ?? locale,
      });
      debugPrint('TTS voice → ${best['name']} (${best['locale']})');
    } catch (e) {
      debugPrint('TTS voice selection failed: $e');
    }
  }

  static String _sttLocaleId(AssistantLanguage l) => switch (l) {
        AssistantLanguage.english => 'en_IN',
        AssistantLanguage.tamil => 'ta_IN',
        AssistantLanguage.hindi => 'hi_IN',
      };

  static String _ttsLocaleId(AssistantLanguage l) => switch (l) {
        AssistantLanguage.english => 'en-IN',
        AssistantLanguage.tamil => 'ta-IN',
        AssistantLanguage.hindi => 'hi-IN',
      };
}

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final svc = VoiceService();
  ref.onDispose(svc.dispose);
  return svc;
});
