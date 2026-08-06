import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sends a WhatsApp message with zero taps via CallMeBot
/// (https://www.callmebot.com) — a free, no-signup API for personal use.
///
/// Why this instead of the official WhatsApp Business API: the official
/// API needs a Meta Business verification and per-message billing, which
/// doesn't fit a feature meant to sit unused until an actual emergency or
/// demo. CallMeBot is free forever with no card on file, at the cost of
/// two real tradeoffs the UI must be upfront about:
///  1. It's an unofficial automation against a personal WhatsApp number,
///     not an approved Business integration — no delivery SLA.
///  2. Each *recipient* number has to opt in once by messaging CallMeBot's
///     own WhatsApp number ("+34 698 28 89 73") with the exact text
///     "I allow callmebot to send me messages", then save the API key it
///     replies with. There's no way around this from the sending side —
///     it's how CallMeBot enforces "personal use only, no spam".
///
/// A contact with no key (see `EmergencyContact.whatsappApiKey`) simply
/// isn't sent to over WhatsApp here — `SosController` falls back to the
/// pre-filled wa.me link for those.
class CallMeBotService {
  CallMeBotService(this._dio);

  final Dio _dio;
  static const _endpoint = 'https://api.callmebot.com/whatsapp.php';

  Future<bool> sendMessage({
    required String phone,
    required String apiKey,
    required String message,
  }) async {
    try {
      final res = await _dio.get<String>(
        _endpoint,
        queryParameters: {'phone': phone, 'text': message, 'apikey': apiKey},
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      // CallMeBot replies 200 with a human-readable status string rather
      // than a structured error code — "Message queued" is success, the
      // handful of documented failure strings all read as an error.
      final body = (res.data ?? '').toLowerCase();
      return body.contains('message queued') || body.contains('message sent');
    } catch (e) {
      dev.log('CallMeBotService.sendMessage failed: $e', name: 'sos.callmebot');
      return false;
    }
  }
}

/// Deliberately not [dioClientProvider] — that attaches the user's Supabase
/// auth token, which has no business going to a third-party public API.
final callMeBotDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
});

final callMeBotServiceProvider = Provider<CallMeBotService>((ref) {
  return CallMeBotService(ref.watch(callMeBotDioProvider));
});
