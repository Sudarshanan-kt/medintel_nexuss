import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/chat_message.dart';

/// Runs a language model on the phone itself.
///
/// The assistant used to reach a model hosted on the backend, which meant it
/// only worked while that machine was running and on the same network. This
/// removes that: inference happens on the device, so the assistant answers
/// with no server, no Wi-Fi and nothing leaving the handset.
///
/// The trade is capability. A 1.5B model that fits in a phone's memory is a
/// weaker reasoner than the 7B on the backend — fine for conversation, and
/// deliberately not used for anything clinical. Interaction verdicts still
/// come from the drug database, and prescription structuring still runs
/// server-side, because neither should be handed to a small model.
///
/// The model is a ~1.6 GB file that is NOT bundled in the app; see
/// [modelFileName] for where it's expected. Until it's present the assistant
/// falls back to its curated replies, exactly as it does when the backend
/// is unreachable.
class OnDeviceLlm {
  /// Qwen2.5 1.5B Instruct, MediaPipe `.task` build, 8-bit.
  ///
  /// Same family as the backend's 7B so the two behave consistently. Chosen
  /// over Gemma because Gemma's weights are licence-gated and would make
  /// every install depend on the user holding a Hugging Face account.
  static const String modelFileName = 'qwen2.5-1.5b-it-q8.task';

  /// Context budget.
  ///
  /// Matches the model build's own cache size exactly. Asking for less made
  /// the OpenCL executor warn on every load — "Recommend to set the max
  /// number of tokens to be the maximum cache size supported by the model,
  /// but got 1024 instead of 1280" — because a mismatch wastes the cache
  /// that was already allocated for the full window.
  static const int _maxTokens = 1280;

  InferenceModel? _model;
  Future<bool>? _loading;
  String? _failure;

  /// One chat kept across turns.
  ///
  /// Recreating it per turn meant re-feeding the whole history every time,
  /// so the model re-processed the entire conversation before it could
  /// start answering — several seconds of prefill that grew with the
  /// conversation. Holding the session keeps the previous turns already in
  /// its cache, so a reply only pays for the new question.
  InferenceChat? _chat;
  AssistantLanguage? _chatLanguage;
  int _turnsInChat = 0;

  /// After this many turns the chat is rebuilt from scratch. The KV cache
  /// grows with every turn and this model's window is 1280 tokens; letting
  /// it run indefinitely ends in a truncated context or an out-of-memory
  /// kill on the phone.
  static const int _maxTurnsPerChat = 8;

  /// Why on-device inference isn't available, or null when it is.
  String? get unavailableReason => _failure;

  bool get isReady => _model != null;

  /// Every place the model file is accepted from, in priority order.
  ///
  /// External app storage comes first because it's the only one reachable
  /// from a computer: on Android that path is
  /// `/sdcard/Android/data/<package>/files`, which `adb push` can write to.
  /// The app's private support directory can't be written from outside
  /// without root, so a model can only get there if the app fetched it —
  /// it's kept as a second location so a future in-app download has
  /// somewhere sensible to land.
  static Future<List<String>> _candidatePaths() async {
    final paths = <String>[];
    try {
      final external = await getExternalStorageDirectory();
      if (external != null) paths.add('${external.path}/$modelFileName');
    } catch (_) {
      // iOS and some Android configurations have no external storage.
    }
    try {
      final support = await getApplicationSupportDirectory();
      paths.add('${support.path}/$modelFileName');
    } catch (_) {
      // Nothing usable; the caller reports the model as missing.
    }
    return paths;
  }

  /// The model file on this device, or null when it isn't installed.
  static Future<String?> modelPath() async {
    for (final path in await _candidatePaths()) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// Where to tell the user to put the file — the sideloadable location.
  static Future<String?> installTargetPath() async {
    final paths = await _candidatePaths();
    return paths.isEmpty ? null : paths.first;
  }

  /// Whether the model file is present on this device.
  static Future<bool> isInstalled() async => (await modelPath()) != null;

  /// Loads the model. Safe to call repeatedly — concurrent callers share one
  /// load, because initialising twice would allocate the weights twice.
  Future<bool> ensureLoaded() {
    if (_model != null) return Future.value(true);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<bool> _load() async {
    try {
      final path = await modelPath();
      if (path == null) {
        _failure = 'The on-device AI model isn\'t installed yet.';
        return false;
      }

      final gemma = FlutterGemmaPlugin.instance;
      await gemma.modelManager.setModelPath(path);

      _model = await gemma.createModel(
        modelType: ModelType.qwen,
        fileType: ModelFileType.task,
        maxTokens: _maxTokens,
        // Ask for the GPU. LiteRT falls back to CPU on its own if the
        // device has no usable OpenCL driver, so this is safe everywhere —
        // it just makes replies several times faster where it works.
        preferredBackend: PreferredBackend.gpu,
      );
      _failure = null;
      return true;
    } catch (e) {
      // Most often out-of-memory on a device that can't hold the weights, or
      // a truncated model file from an interrupted copy.
      debugPrint('OnDeviceLlm load failed: $e');
      _failure = 'The on-device AI model could not be loaded on this phone.';
      _model = null;
      return false;
    }
  }

  /// The chat to use for this turn, reusing the existing one where possible.
  ///
  /// Rebuilt when the language changes (the system prompt differs) or when
  /// the turn budget is spent.
  Future<InferenceChat> _chatFor(
    String systemPrompt,
    AssistantLanguage language,
    List<({bool isUser, String text})> history,
  ) async {
    final reusable = _chat != null &&
        _chatLanguage == language &&
        _turnsInChat < _maxTurnsPerChat;
    if (reusable) return _chat!;

    final chat = await _model!.createChat(
      temperature: 0.7,
      topK: 40,
      topP: 0.95,
      modelType: ModelType.qwen,
      systemInstruction: systemPrompt,
    );

    // Only when starting fresh does the recent history need replaying, so
    // the model still has the thread of the conversation.
    for (final turn
        in history.length > 4 ? history.sublist(history.length - 4) : history) {
      if (turn.text.trim().isEmpty) continue;
      await chat.addQueryChunk(
        Message.text(text: turn.text, isUser: turn.isUser),
      );
    }

    _chat = chat;
    _chatLanguage = language;
    _turnsInChat = 0;
    return chat;
  }

  /// Streams a reply token by token.
  ///
  /// Streaming is what makes this feel responsive: the full answer still
  /// takes as long to generate, but the first words appear almost
  /// immediately instead of after several seconds of blank screen.
  ///
  /// Yields nothing at all when the model isn't usable, so callers can fall
  /// back rather than showing an empty answer.
  Stream<String> generateStream({
    required String systemPrompt,
    required AssistantLanguage language,
    required List<({bool isUser, String text})> history,
    required String prompt,
  }) async* {
    if (!await ensureLoaded()) return;

    try {
      final chat = await _chatFor(systemPrompt, language, history);
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
      _turnsInChat++;

      await for (final response in chat.generateChatResponseAsync()) {
        if (response case TextResponse(:final token)) {
          if (token.isNotEmpty) yield token;
        }
      }
    } catch (e) {
      debugPrint('OnDeviceLlm stream failed: $e');
      // A failed turn can leave the session's cache inconsistent, so drop
      // it rather than carrying the damage into the next question.
      _chat = null;
      _turnsInChat = 0;
    }
  }

  /// Generates a whole reply. Returns null when the model isn't usable.
  Future<String?> generate({
    required String systemPrompt,
    required AssistantLanguage language,
    required List<({bool isUser, String text})> history,
    required String prompt,
  }) async {
    final buffer = StringBuffer();
    await for (final token in generateStream(
      systemPrompt: systemPrompt,
      language: language,
      history: history,
      prompt: prompt,
    )) {
      buffer.write(token);
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  /// Drops the conversation without unloading the model — for when the user
  /// starts a new topic and the old context is just cost.
  void resetConversation() {
    _chat = null;
    _turnsInChat = 0;
  }

  Future<void> dispose() async {
    _chat = null;
    await _model?.close();
    _model = null;
  }
}

final onDeviceLlmProvider = Provider<OnDeviceLlm>((ref) {
  final llm = OnDeviceLlm();
  ref.onDispose(llm.dispose);
  return llm;
});
