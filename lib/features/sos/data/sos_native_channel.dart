import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bridges to the native Android SMS/call channel (see `MainActivity.kt`)
/// that sends SMS and places calls with zero UI — no dialer screen, no
/// message composer, no tap to send.
///
/// Android-only by construction: iOS has no API that lets a third-party
/// app send an SMS or place a call without the user confirming in the
/// system UI, so the channel simply isn't registered there. Every method
/// here fails soft (returns false) rather than throwing, so callers can
/// always fall back to `url_launcher`'s tel:/sms: (which open the native
/// app pre-filled, needing one tap) without special-casing the platform
/// themselves.
class SosNativeChannel {
  static const _channel = MethodChannel('medintel/sos');

  Future<bool> hasPermissions() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermissions') ?? false;
    } catch (e) {
      debugPrint('SosNativeChannel.hasPermissions failed: $e');
      return false;
    }
  }

  /// Prompts for SEND_SMS + CALL_PHONE and returns whether both were
  /// granted. Safe to call repeatedly — a no-op if already granted.
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermissions') ?? false;
    } catch (e) {
      debugPrint('SosNativeChannel.requestPermissions failed: $e');
      return false;
    }
  }

  /// Sends [message] to [phone] with no compose screen. Returns false
  /// (never throws) if the permission isn't granted, the platform isn't
  /// Android, or the underlying SmsManager call fails for any reason —
  /// callers should treat false as "fall back to the tap-to-send path".
  Future<bool> sendSms({required String phone, required String message}) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('sendSms', {
            'phone': phone,
            'message': message,
          }) ??
          false;
    } catch (e) {
      debugPrint('SosNativeChannel.sendSms failed: $e');
      return false;
    }
  }

  /// Places a call to [phone] directly — no dialer screen. Returns false
  /// under the same conditions as [sendSms].
  Future<bool> placeCall(String phone) async {
    if (kIsWeb) return false;
    try {
      return await _channel.invokeMethod<bool>('placeCall', {'phone': phone}) ??
          false;
    } catch (e) {
      debugPrint('SosNativeChannel.placeCall failed: $e');
      return false;
    }
  }
}

final sosNativeChannelProvider = Provider<SosNativeChannel>((ref) {
  return SosNativeChannel();
});
