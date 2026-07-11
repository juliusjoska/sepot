@Tags(['tor'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/constants/app_constants.dart';
import 'package:sepot/core/network/relay_transport.dart';

/// Živý smoke [TorTransport] proti REÁLNÉMU onion relayi přes Tor.
/// Vyžaduje běžící SOCKS proxy na 127.0.0.1:9050 (Orbot / lokální tor) —
/// jinak se testy SAMY skipnou, aby `flutter test` na strojích bez toru
/// neselhal.
///   flutter test test/network/tor_transport_live_test.dart --tags tor
void main() {
  const socksPort = 9050;

  Future<bool> socksUp() async {
    try {
      final s = await Socket.connect('127.0.0.1', socksPort,
          timeout: const Duration(seconds: 1));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  test('REST /v1/server-info přes onion → 200 + trust_root', () async {
    if (!await socksUp()) {
      markTestSkipped('Tor SOCKS 127.0.0.1:$socksPort neběží');
      return;
    }
    final t = TorTransport(socksPort: socksPort);
    final resp = await t
        .httpClient()
        .get(Uri.parse('${AppConstants.relayOnion}/v1/server-info'))
        .timeout(const Duration(seconds: 60));
    expect(resp.statusCode, 200);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    expect(body['trust_root'], isNotNull);
    expect(body['capabilities'], contains('sealed-sender'));
    t.close();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('WS /v1/ws přes onion → upgrade projde (obousměrný tunel)', () async {
    if (!await socksUp()) {
      markTestSkipped('Tor SOCKS 127.0.0.1:$socksPort neběží');
      return;
    }
    final t = TorTransport(socksPort: socksPort);
    final wsUrl = AppConstants.relayOnion.replaceFirst('http', 'ws');
    final ch = t.connectWs(Uri.parse('$wsUrl/v1/ws'));
    // Dokončení `ready` = HTTP Upgrade (101) prošel skrz Tor tunel k onion.
    await ch.ready.timeout(const Duration(seconds: 60));
    expect(ch.closeCode, isNull); // spojení stojí
    await ch.sink.close();
    t.close();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
