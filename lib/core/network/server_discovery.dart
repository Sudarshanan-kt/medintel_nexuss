import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Finds the backend on whatever Wi-Fi the phone is currently on.
///
/// The backend runs on a laptop with a DHCP address, so its IP changes with
/// every network — a different Wi-Fi, a new lease, a router reboot. Baking one
/// address into the build (or typing it into settings) means the app works on
/// exactly one network and silently fails everywhere else.
///
/// Rather than ask the user to find their laptop's IP, this sweeps the phone's
/// own subnet for something answering this app's `/health`. A /24 is only 254
/// addresses; probed in parallel with a short timeout that's a few seconds.
///
/// Answering is not enough to be adopted. Everything this app sends the
/// backend — a Supabase bearer token, prescriptions, lab results — would go
/// to whatever host replied first, and on café, hospital or campus Wi-Fi that
/// is not a host we chose. So a candidate has to prove it holds the pairing
/// code printed by `scripts/run.sh`: see [verify]. No pairing code, no sweep.
///
/// Deliberately not mDNS/Bonjour: it needs a native plugin, an extra Android
/// permission, and is unreliable on networks that block multicast — which is
/// most guest and campus Wi-Fi, exactly where this needs to work.
abstract final class ServerDiscovery {
  /// The port the backend is documented to run on (`--port 8000`).
  static const int port = 8000;

  /// Per-host budget. A machine on the same LAN answers in single-digit
  /// milliseconds; anything slower is almost certainly not there, and waiting
  /// longer multiplies across 254 hosts.
  static const Duration _hostTimeout = Duration(milliseconds: 600);

  /// How many probes are in flight at once. High enough to sweep a /24 in a
  /// few seconds, low enough not to exhaust the socket limit.
  static const int _concurrency = 48;

  static final Random _random = Random.secure();

  /// Scans every IPv4 subnet the phone is on and returns the first base URL
  /// that proves it is this app's backend, or null if none does.
  ///
  /// [pairingCode] is the code the backend printed on startup. Empty means
  /// nothing found can be told apart from an impostor, so nothing is
  /// returned and no probes are sent at all.
  ///
  /// [onProgress] reports hosts probed so far, for a progress indicator.
  static Future<String?> find({
    required String pairingCode,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pairingCode.isEmpty) return null;

    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) return null;

    for (final prefix in prefixes) {
      final found = await _scanPrefix(
        prefix,
        pairingCode,
        onProgress: onProgress,
      );
      if (found != null) return found;
    }
    return null;
  }

  /// Whether the server at [baseUrl] holds [pairingCode].
  ///
  /// Asks for a proof over a nonce this app just made up, so the answer is
  /// different every time and a host that overhears one exchange has nothing
  /// to replay. The code itself never goes over the wire.
  ///
  /// False whenever that can't be shown — unreachable, not this app's
  /// backend, or a backend running without a `DISCOVERY_SECRET` and so
  /// unable to prove anything. Failing closed is the point: this is the
  /// check that decides whether to send a bearer token and health records to
  /// an address nobody typed in.
  static Future<bool> verify(
    String baseUrl,
    String pairingCode, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (baseUrl.isEmpty || pairingCode.isEmpty) return false;

    final nonce = _nonce();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/health?nonce=$nonce'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return false;

      // Bounded: an unverified host is choosing this response, and a stream
      // that never ends would hold the sweep open for its whole timeout.
      final body = await response
          .take(2048)
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;

      final proof = decoded['proof'];
      if (proof is! String) return false;
      return _constantTimeEquals(proof, _expectedProof(pairingCode, nonce));
    } on Object {
      // Unreachable, not HTTP, not JSON, truncated mid-object — none of it
      // distinguishes "wrong host" from "broken host", and both mean no.
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// A fresh 128-bit challenge, hex encoded.
  static String _nonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// What a server holding [pairingCode] must return for [nonce]. Mirrors
  /// `security.discovery_proof` on the backend.
  static String _expectedProof(String pairingCode, String nonce) {
    return Hmac(sha256, utf8.encode(pairingCode))
        .convert(utf8.encode(nonce))
        .toString();
  }

  /// Compares without leaking, in how long it takes, how much of the proof
  /// was right. Cheap here, and the alternative is a timing oracle that
  /// lets an attacker on the LAN build a valid proof a byte at a time.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// The `a.b.c.` prefixes of every non-loopback IPv4 address the phone holds.
  ///
  /// Usually one (Wi-Fi). On mobile data there is no LAN peer to find, and
  /// the carrier's ranges are not worth sweeping, so those are skipped.
  static Future<List<String>> _localPrefixes() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final prefixes = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          if (!_isPrivate(parts)) continue;
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}.');
        }
      }
      return prefixes.toList();
    } on Object {
      return const [];
    }
  }

  /// RFC1918 only. A public address here means mobile data or a carrier NAT,
  /// where sweeping 254 hosts would be pointless and rude.
  static bool _isPrivate(List<String> octets) {
    final a = int.tryParse(octets[0]) ?? -1;
    final b = int.tryParse(octets[1]) ?? -1;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static Future<String?> _scanPrefix(
    String prefix,
    String pairingCode, {
    void Function(int done, int total)? onProgress,
  }) async {
    const total = 254;
    var done = 0;

    for (var start = 1; start <= total; start += _concurrency) {
      final batch = <Future<String?>>[];
      for (var i = start; i < start + _concurrency && i <= total; i++) {
        batch.add(_probe('$prefix$i', pairingCode));
      }
      final results = await Future.wait(batch);
      done += batch.length;
      onProgress?.call(done, total);

      for (final hit in results) {
        if (hit != null) return hit;
      }
    }
    return null;
  }

  /// One host. Returns its base URL if it proves it is this backend.
  static Future<String?> _probe(String host, String pairingCode) async {
    final url = 'http://$host:$port';
    final ours = await verify(url, pairingCode, timeout: _hostTimeout);
    return ours ? url : null;
  }
}
