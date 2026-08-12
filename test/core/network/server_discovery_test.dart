import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medintel_nexus/core/network/server_discovery.dart';

/// A stand-in for whatever is listening on port 8000 of some address the LAN
/// sweep probes — the real backend, or a machine that only wants to look
/// like it.
///
/// [respond] gets the nonce the app sent and returns the body to answer with,
/// which is the whole surface an impostor has to work with.
Future<HttpServer> _serve(String Function(String nonce) respond) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final nonce = request.uri.queryParameters['nonce'] ?? '';
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(respond(nonce));
    await request.response.close();
  });
  return server;
}

String _proofFor(String secret, String nonce) =>
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(nonce)).toString();

void main() {
  const code = '0123456789abcdef0123456789abcdef';

  late HttpServer server;
  String url() => 'http://127.0.0.1:${server.port}';

  tearDown(() => server.close(force: true));

  test('accepts a server that proves it holds the pairing code', () async {
    server = await _serve(
      (nonce) => jsonEncode({
        'status': 'ok',
        'proof': _proofFor(code, nonce),
      }),
    );

    expect(await ServerDiscovery.verify(url(), code), isTrue);
  });

  test('rejects a host that only answers ok', () async {
    // The reason any of this exists. On shared Wi-Fi anything can return a
    // healthy-looking /health, and adopting it would send it a bearer token
    // and the patient's prescriptions.
    server = await _serve((_) => jsonEncode({'status': 'ok'}));

    expect(await ServerDiscovery.verify(url(), code), isFalse);
  });

  test('rejects a proof computed with the wrong secret', () async {
    server = await _serve(
      (nonce) => jsonEncode({
        'status': 'ok',
        'proof': _proofFor('not-the-pairing-code', nonce),
      }),
    );

    expect(await ServerDiscovery.verify(url(), code), isFalse);
  });

  test('rejects a proof replayed from an earlier exchange', () async {
    // A host that overheard one valid answer learns nothing reusable,
    // because the nonce it has to answer is new every time.
    final stale = _proofFor(code, 'a-nonce-from-before');
    server = await _serve(
      (_) => jsonEncode({'status': 'ok', 'proof': stale}),
    );

    expect(await ServerDiscovery.verify(url(), code), isFalse);
  });

  test('rejects a backend running without a discovery secret', () async {
    // What the real backend returns when DISCOVERY_SECRET is unset: honest,
    // and still not adoptable, because it can't be told from an impostor.
    server = await _serve((_) => jsonEncode({'status': 'ok', 'proof': null}));

    expect(await ServerDiscovery.verify(url(), code), isFalse);
  });

  test('rejects a host answering with something other than JSON', () async {
    server = await _serve((_) => '<html>router admin</html>');

    expect(await ServerDiscovery.verify(url(), code), isFalse);
  });

  test('verifies nothing when the phone has no pairing code', () async {
    server = await _serve(
      (nonce) => jsonEncode({
        'status': 'ok',
        'proof': _proofFor(code, nonce),
      }),
    );

    expect(await ServerDiscovery.verify(url(), ''), isFalse);
  });

  test('does not sweep at all without a pairing code', () async {
    // Fails closed rather than falling back to the old behaviour of taking
    // whichever host replied first.
    server = await _serve((_) => jsonEncode({'status': 'ok'}));

    expect(await ServerDiscovery.find(pairingCode: ''), isNull);
  });
}
