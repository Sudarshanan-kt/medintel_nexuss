import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoints.dart';
import 'server_discovery.dart';

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

  /// Whether the stored address was typed in rather than auto-detected.
  static const _manualKey = 'medintel_api_base_url_manual';

  /// How long after a fruitless sweep to wait before starting another.
  ///
  /// A sweep is 254 probes. Without this, a backend that is simply switched
  /// off would have every failed request kick off a fresh scan of the
  /// network, and a screen that makes several calls would run several at
  /// once.
  static const Duration _sweepCooldown = Duration(seconds: 20);

  /// True while [autoDetect] is sweeping the LAN, so the settings UI can show
  /// progress instead of looking frozen.
  bool isDetecting = false;

  Future<bool>? _inFlight;
  DateTime? _lastSweep;

  /// True when the current address was chosen by a person, which makes it
  /// off-limits to automatic re-detection. See [_ensureReachable].
  bool _chosenByUser = false;

  /// The address requests currently go to.
  ///
  /// For callers holding the notifier rather than watching the provider —
  /// see `dio_client.dart`, which has to read the re-detected address from
  /// inside an interceptor.
  String get baseUrl => state;

  @override
  String build() {
    _restore();
    _watchNetworkChanges();
    return ApiEndpoints.baseUrl;
  }

  /// Re-checks the backend whenever the phone changes network.
  ///
  /// Resolving the address once at launch is not enough. An app that started
  /// on mobile data, or before Wi-Fi finished associating, would hold an
  /// address that answers nowhere until it was force-quit — and since the
  /// backend's DHCP address differs on every network, so would an app that
  /// simply moved from one Wi-Fi to another. Both look, from the outside,
  /// like "these features only work at my friend's place".
  void _watchNetworkChanges() {
    try {
      final sub = Connectivity().onConnectivityChanged.listen(
        (_) => unawaited(ensureReachable(force: true)),
      );
      ref.onDispose(sub.cancel);
    } on Object {
      // No connectivity plugin on this platform. Startup and per-failure
      // healing still apply; only the proactive re-check is lost.
    }
  }

  /// Confirms the current address still answers, and goes looking for the
  /// backend if it doesn't. Returns whether the app can reach one.
  ///
  /// Safe to call from anywhere as often as you like: concurrent callers
  /// share a single check, and sweeps are rate-limited by [_sweepCooldown].
  /// Pass [force] when something already implies the network moved.
  Future<bool> ensureReachable({bool force = false}) {
    return _inFlight ??= _ensureReachable(force).whenComplete(() {
      _inFlight = null;
    });
  }

  Future<bool> _ensureReachable(bool force) async {
    if (await _answers(state)) return true;

    // A typed-in address is never swapped out from under the user. Automatic
    // detection exists for one situation — a backend on a laptop whose DHCP
    // address moves — and it can only ever find something on the current
    // LAN. An address reached over Tailscale, a tunnel or a real deployment
    // is stable and works on mobile data, so "healing" it into a 192.168.x
    // address would break exactly the case it was set up for, and would do
    // it silently. The settings screen's detect button is the way to change
    // it.
    if (_chosenByUser) return false;

    final last = _lastSweep;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _sweepCooldown) {
      return false;
    }
    _lastSweep = DateTime.now();

    final found = await ServerDiscovery.find();
    if (found == null) return false;
    if (found != state) await setBaseUrl(found);
    return true;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.trim().isNotEmpty) state = saved.trim();
      _chosenByUser = prefs.getBool(_manualKey) ?? false;
    } catch (_) {
      // Keep the compiled-in default; an unreadable preference store is not
      // a reason to fail to start.
    }
    // Whatever address we ended up with was correct on *some* network. The
    // backend's IP moves with every Wi-Fi change, so confirm it still answers
    // and go looking if it doesn't.
    //
    // Deliberately quiet: the address is a deployment detail, and a user who
    // switched networks has no reason to care that it changed. Anything found
    // is persisted, so the next launch starts correct.
    unawaited(ensureReachable());
  }

  /// Sweeps the current network for the backend and adopts it if found.
  ///
  /// Returns the address found, or null. Exposed for the settings screen's
  /// "detect automatically" action.
  Future<String?> autoDetect({
    void Function(int done, int total)? onProgress,
  }) async {
    isDetecting = true;
    try {
      final found = await ServerDiscovery.find(onProgress: onProgress);
      // Asking to detect is asking to hand the address back to automation,
      // so this clears any earlier manual choice.
      if (found != null) await setBaseUrl(found, chosenByUser: false);
      return found;
    } finally {
      isDetecting = false;
    }
  }

  /// Whether [url] is this app's backend, right now.
  static Future<bool> _answers(String url) async {
    if (url.isEmpty) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client
          .getUrl(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return false;
      final body = await res
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 3));
      return body.contains('ok');
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Saves [url] and points every subsequent request at it.
  ///
  /// Normalises the two things people actually type: a missing scheme, and
  /// a trailing slash that would produce `//api/v1/...` once endpoint paths
  /// are appended.
  ///
  /// [chosenByUser] marks the address as typed in rather than found, which
  /// protects it from automatic re-detection.
  Future<void> setBaseUrl(String url, {bool chosenByUser = false}) async {
    final normalised = normalise(url);
    if (normalised.isEmpty) return;
    state = normalised;
    _chosenByUser = chosenByUser;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, normalised);
      await prefs.setBool(_manualKey, chosenByUser);
    } catch (_) {
      // In-memory value still applies for this session.
    }
  }

  /// Returns to the address compiled into this build.
  Future<void> reset() async {
    state = ApiEndpoints.baseUrl;
    _chosenByUser = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_manualKey);
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
