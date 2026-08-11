import 'dart:async';
import 'dart:io';

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

  /// Scans every IPv4 subnet the phone is on and returns the first base URL
  /// that answers as this app's backend, or null if nothing does.
  ///
  /// [onProgress] reports hosts probed so far, for a progress indicator.
  static Future<String?> find({
    void Function(int done, int total)? onProgress,
  }) async {
    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) return null;

    for (final prefix in prefixes) {
      final found = await _scanPrefix(prefix, onProgress: onProgress);
      if (found != null) return found;
    }
    return null;
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
    String prefix, {
    void Function(int done, int total)? onProgress,
  }) async {
    const total = 254;
    var done = 0;

    for (var start = 1; start <= total; start += _concurrency) {
      final batch = <Future<String?>>[];
      for (var i = start; i < start + _concurrency && i <= total; i++) {
        batch.add(_probe('$prefix$i'));
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

  /// One host. Returns its base URL if it answers as this backend.
  ///
  /// Checks the body, not just that something replied: a router admin page or
  /// a printer on port 8000 would happily return 200 for `/health`, and
  /// adopting one as the server would be worse than finding nothing.
  static Future<String?> _probe(String host) async {
    final client = HttpClient()
      ..connectionTimeout = _hostTimeout
      ..idleTimeout = _hostTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/health'))
          .timeout(_hostTimeout);
      final response = await request.close().timeout(_hostTimeout);
      if (response.statusCode != 200) return null;
      final body = await response
          .take(1024)
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(_hostTimeout);
      if (!body.contains('"status"') || !body.contains('ok')) return null;
      return 'http://$host:$port';
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
