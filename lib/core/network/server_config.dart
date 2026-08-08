import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoints.dart';

/// Where the app's backend lives, changeable without a rebuild.
///
/// The compiled-in `API_BASE_URL` is only a default. On a laptop the backend
/// sits on a DHCP address that changes with every network — a different
/// Wi-Fi, a new lease — and baking that into the APK meant a ten-minute
/// rebuild and reinstall each time it moved. The address is a deployment
/// detail, so it lives in settings.
///
/// Nothing here validates that the server is real; [ServerConfig.probe] is
/// offered so the settings UI can check before saving, but a bad address is
/// always recoverable by editing it again.
class ServerConfig extends Notifier<String> {
  static const _key = 'medintel_api_base_url';

  @override
  String build() {
    _restore();
    return ApiEndpoints.baseUrl;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.trim().isNotEmpty) state = saved.trim();
    } catch (_) {
      // Keep the compiled-in default; an unreadable preference store is not
      // a reason to fail to start.
    }
  }

  /// Saves [url] and points every subsequent request at it.
  ///
  /// Normalises the two things people actually type: a missing scheme, and
  /// a trailing slash that would produce `//api/v1/...` once endpoint paths
  /// are appended.
  Future<void> setBaseUrl(String url) async {
    final normalised = normalise(url);
    if (normalised.isEmpty) return;
    state = normalised;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, normalised);
    } catch (_) {
      // In-memory value still applies for this session.
    }
  }

  /// Returns to the address compiled into this build.
  Future<void> reset() async {
    state = ApiEndpoints.baseUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static String normalise(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      // Plain http: this is a LAN address in practice, and https would need
      // a certificate the machine doesn't have.
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}

final serverConfigProvider = NotifierProvider<ServerConfig, String>(
  ServerConfig.new,
);
