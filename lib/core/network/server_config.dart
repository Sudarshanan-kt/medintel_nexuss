import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  /// The pairing code, kept in the keystore rather than SharedPreferences:
  /// it is the one value here that is a secret, and anything holding it can
  /// impersonate the backend to this app.
  static const _pairingKey = 'medintel_pairing_code';

  static const _secureStore = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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

  String _pairingCode = '';

  /// The code this app checks a discovered server against, or empty if the
  /// phone has not been paired with a backend yet. Printed by the backend's
  /// `scripts/run.sh` on startup.
  String get pairingCode => _pairingCode;

  /// Whether a person or a build chose the current address, rather than a
  /// network scan finding it.
  ///
  /// The distinction decides how much proof the address has to offer. A
  /// typed-in or compiled-in address is somebody's stated intent, and
  /// answering is enough to believe it. A swept one is whichever host on the
  /// current Wi-Fi replied first, which on a network we don't own is not a
  /// reason to send it a bearer token — that one has to prove itself.
  bool get _addressAsserted => _chosenByUser || state == ApiEndpoints.baseUrl;

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
    // LAN. An address reached over a tunnel or a real deployment is stable
    // and works off-LAN, so "healing" it into a 192.168.x
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

    final found = await ServerDiscovery.find(pairingCode: _pairingCode);
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
    try {
      _pairingCode = await _secureStore.read(key: _pairingKey) ?? '';
    } catch (_) {
      // No code means discovery stays off and a stored discovered address
      // can't be re-verified, which is the safe way to fail.
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

  /// Stores the code that discovered servers are checked against.
  ///
  /// Tolerant about how it's entered: the code is 32 hex characters read off
  /// a terminal and typed on a phone, so spacing, dashes and case are the
  /// user's business, not the comparison's.
  Future<void> setPairingCode(String code) async {
    _pairingCode = normalisePairingCode(code);
    try {
      if (_pairingCode.isEmpty) {
        await _secureStore.delete(key: _pairingKey);
      } else {
        await _secureStore.write(key: _pairingKey, value: _pairingCode);
      }
    } catch (_) {
      // In-memory value still applies for this session.
    }
  }

  static String normalisePairingCode(String raw) {
    return raw.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
  }

  /// Sweeps the current network for the backend and adopts it if it proves
  /// it holds the pairing code.
  ///
  /// Returns the address found, or null — including when no pairing code is
  /// set, which is when there is no way to tell the backend from anything
  /// else that answers and so nothing is swept at all.
  Future<String?> autoDetect({
    void Function(int done, int total)? onProgress,
  }) async {
    isDetecting = true;
    try {
      final found = await ServerDiscovery.find(
        pairingCode: _pairingCode,
        onProgress: onProgress,
      );
      // Asking to detect is asking to hand the address back to automation,
      // so this clears any earlier manual choice.
      if (found != null) await setBaseUrl(found, chosenByUser: false);
      return found;
    } finally {
      isDetecting = false;
    }
  }

  /// Whether [url] is this app's backend, right now.
  ///
  /// How hard that is to show depends on where the address came from — see
  /// [_addressAsserted]. A discovered one has to prove it holds the pairing
  /// code, every time, because the host at a given IP changes with the
  /// network while the stored address doesn't: the laptop at 192.168.1.5 at
  /// home is a stranger's machine at 192.168.1.5 in a café.
  Future<bool> _answers(String url) async {
    if (url.isEmpty) return false;
    if (!_addressAsserted) {
      return _pairingCode.isNotEmpty &&
          await ServerDiscovery.verify(url, _pairingCode);
    }
    return _isAlive(url);
  }

  /// Whether anything is serving this app's `/health` at [url]. Liveness
  /// only — it says something answered, not who.
  static Future<bool> _isAlive(String url) async {
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
  ///
  /// Leaves the pairing code alone: it belongs to a backend rather than to
  /// an address, survives the machine moving networks, and is the tedious
  /// thing to re-enter.
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
