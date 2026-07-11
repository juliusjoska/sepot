/// Transport relaye: JAK se navazují REST i WS spojení.
///
/// Dvě varianty se stejným rozhraním, aby [RelayClient] nevěděl, kudy
/// data tečou:
///   - [DirectTransport] — přímé šifrované spojení (HTTPS/WSS) na
///     `relay.sepot.cz`. Default.
///   - [TorTransport] — všechna spojení jdou přes lokální SOCKS5 proxy
///     (Orbot) na `.onion` adresu relaye. IP klienta se k relayi nikdy
///     nedostane; jméno `.onion` resolvuje Tor (klient sám DNS nedělá →
///     žádný únik dotazu).
///
/// Přepínání je runtime záležitost (viz `MessagingService.setTorEnabled`):
/// změna transportu = přestavení [RelayClient] s novou instancí.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Abstrakce nad tím, jak klient otevírá spojení k relayi.
abstract class RelayTransport {
  /// Sdílený HTTP klient pro REST (registrace, prekey bundle, přílohy…).
  http.Client httpClient();

  /// Naváže WebSocket na [url].
  WebSocketChannel connectWs(Uri url);

  /// Uvolní podkladové klienty. Po zavření se transport už nepoužívá.
  void close();
}

/// Přímé spojení bez proxy — HTTPS/WSS rovnou na relay.
class DirectTransport implements RelayTransport {
  http.Client? _client;

  @override
  http.Client httpClient() => _client ??= http.Client();

  @override
  WebSocketChannel connectWs(Uri url) => WebSocketChannel.connect(url);

  @override
  void close() {
    _client?.close();
    _client = null;
  }
}

/// Tor: REST i WS se tunelují přes SOCKS5 proxy (výchozí Orbot na
/// `127.0.0.1:9050`). Onion adresa se do SOCKS CONNECT posílá jako
/// doména (ATYP=0x03), takže její resolvování obstará Tor.
///
/// Jeden [HttpClient] slouží REST i WS — WS upgrade jede přes stejnou
/// connectionFactory (SOCKS socket), takže se tuneluje stejně.
class TorTransport implements RelayTransport {
  TorTransport({this.socksHost = '127.0.0.1', this.socksPort = 9050});

  /// Adresa SOCKS5 proxy. Orbot výchozí je `127.0.0.1:9050`.
  final String socksHost;
  final int socksPort;

  HttpClient? _httpClient;
  IOClient? _ioClient;

  HttpClient _sharedHttpClient() {
    final client = _httpClient;
    if (client != null) return client;
    final built = HttpClient();
    // Nastaví connectionFactory tak, aby každé spojení šlo přes SOCKS5.
    // Onion je http:// — Tor obálka šifruje, TLS uvnitř netřeba.
    SocksTCPClient.assignToHttpClient(built, [
      ProxySettings(InternetAddress(socksHost), socksPort),
    ]);
    return _httpClient = built;
  }

  @override
  http.Client httpClient() => _ioClient ??= IOClient(_sharedHttpClient());

  @override
  WebSocketChannel connectWs(Uri url) =>
      IOWebSocketChannel.connect(_withExplicitPort(url),
          customClient: _sharedHttpClient());

  /// `Uri` pro `ws`/`wss` nezná výchozí port → `url.port` vrací 0 a SOCKS
  /// CONNECT by cílil na port 0 (serverError). Doplníme ho podle schématu
  /// (ws→80, wss→443). U přímého transportu to řeší WS klient sám, tady
  /// port protéká až do connectionFactory, tak ho musíme dodat.
  static Uri _withExplicitPort(Uri url) {
    if (url.hasPort) return url;
    final port = url.scheme == 'wss' ? 443 : 80;
    return url.replace(port: port);
  }

  @override
  void close() {
    // IOClient.close() zavře i sdílený HttpClient; force pro jistotu
    // strhne i případné živé WS spojení.
    _ioClient?.close();
    _ioClient = null;
    _httpClient?.close(force: true);
    _httpClient = null;
  }
}
