import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sepot/core/network/relay_transport.dart';
import 'package:socks5_proxy/socks_server.dart';

/// Deterministické ověření [TorTransport]: REST i WS musí projít lokálním
/// SOCKS5 serverem k lokálnímu cílovému serveru. Žádná síť ven, žádný
/// libsignal — jen transportní vrstva. Doplňuje živý smoke proti onion
/// (`tor_transport_live_test.dart`, tag `tor`).
void main() {
  group('TorTransport přes lokální SOCKS5 proxy', () {
    late SocksServer proxy;
    late int proxyPort;
    late HttpServer target;
    late int targetPort;

    setUp(() async {
      // SOCKS5 proxy, která každý požadavek prostě forwarduje na cíl.
      proxy = SocksServer();
      proxy.connections.listen((c) async {
        try {
          await c.forward();
        } catch (_) {
          // klient zavřel dřív — pro test nepodstatné
        }
      }).onError((_) {});
      final proxySock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      proxyPort = proxySock.port;
      await proxy.addServerSocket(proxySock);

      // Cílový server: echo HTTP + echo WebSocket.
      target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      targetPort = target.port;
      target.listen((req) async {
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((data) => ws.add(data)); // echo zpět
        } else {
          req.response
            ..statusCode = 200
            ..write('ozvěna:${req.uri.path}');
          await req.response.close();
        }
      });
    });

    tearDown(() async {
      await target.close(force: true);
      await proxy.stop();
    });

    test('REST GET projde přes proxy k cíli', () async {
      final t = TorTransport(socksHost: '127.0.0.1', socksPort: proxyPort);
      final resp = await t
          .httpClient()
          .get(Uri.parse('http://127.0.0.1:$targetPort/ahoj'))
          .timeout(const Duration(seconds: 10));
      expect(resp.statusCode, 200);
      expect(resp.body, 'ozvěna:/ahoj');
      t.close();
    });

    test('WebSocket se otevře přes proxy a echuje', () async {
      final t = TorTransport(socksHost: '127.0.0.1', socksPort: proxyPort);
      final ch = t.connectWs(Uri.parse('ws://127.0.0.1:$targetPort/v1/ws'));
      await ch.ready.timeout(const Duration(seconds: 10));
      ch.sink.add('ping-přes-tor');
      final echo = await ch.stream.first.timeout(const Duration(seconds: 10));
      expect(echo, 'ping-přes-tor');
      await ch.sink.close();
      t.close();
    });

    test('DirectTransport míří na cíl přímo (kontrolní vzorek)', () async {
      final t = DirectTransport();
      final resp = await t
          .httpClient()
          .get(Uri.parse('http://127.0.0.1:$targetPort/primo'))
          .timeout(const Duration(seconds: 10));
      expect(resp.statusCode, 200);
      expect(resp.body, 'ozvěna:/primo');
      t.close();
    });
  });
}
