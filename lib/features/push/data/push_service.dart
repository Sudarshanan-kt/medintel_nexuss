import 'dart:developer' as dev;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thin wrapper around Firebase Cloud Messaging: permission request, token
/// retrieval, and displaying a local notification for foreground messages
/// (FCM does not auto-display a system notification while the app is in
/// the foreground — only background/terminated states do that natively).
///
/// Every method is best-effort: if Firebase hasn't been initialised (e.g.
/// local dev without firebase_options.dart configured yet), calls fail
/// silently rather than crashing the app — push is an enhancement, never a
/// hard dependency for the rest of the app to function.
class PushService {
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _localInitialized = false;

  // Web Push certificate public key (Firebase Console → Project Settings →
  // Cloud Messaging → Web Push certificates). Public by design — safe to
  // embed in client code, same as the Firebase web apiKey. Ignored on
  // Android/iOS.
  static const _webVapidKey =
      'BE4BxNtQH6JwqVVpz1eZbxed2_oXlki5Q-lHkzKFvITIoM49ZZv6lIIYUVJPN00lSwdNHb6-qJ8FksmwkgTAZK4';

  void _log(String msg) => dev.log(msg, name: 'push.service');

  Future<void> _ensureLocalInitialized() async {
    if (_localInitialized || kIsWeb) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
    );
    _localInitialized = true;
  }

  /// Requests permission and returns the current FCM token, or null if
  /// permission was denied or Firebase isn't available.
  Future<String?> requestPermissionAndGetToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        _log('Notification permission denied');
        return null;
      }
      return await messaging.getToken(
        vapidKey: kIsWeb ? _webVapidKey : null,
      );
    } catch (e) {
      _log('requestPermissionAndGetToken failed (Firebase not configured?): $e');
      return null;
    }
  }

  Stream<String> get onTokenRefresh {
    try {
      return FirebaseMessaging.instance.onTokenRefresh;
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Shows a local notification for a message that arrived while the app
  /// was open. Call once, early — safe to call multiple times.
  void listenForegroundMessages() {
    try {
      FirebaseMessaging.onMessage.listen((message) async {
        final title = message.notification?.title ?? 'MedIntel Nexus';
        final body = message.notification?.body ?? '';
        if (kIsWeb) return; // Browser notification API path not wired yet.
        await _ensureLocalInitialized();
        await _local.show(
          message.hashCode,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'medintel_push',
              'Alerts',
              channelDescription: 'Care Circle and risk alerts',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      });
    } catch (e) {
      _log('listenForegroundMessages failed: $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService());
