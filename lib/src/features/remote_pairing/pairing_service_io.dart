import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'pairing_protocol.dart';
import 'pairing_service.dart';

PhonePairingService createPhonePairingService() => IoPhonePairingService();

class IoPhonePairingService implements PhonePairingService {
  IoPhonePairingService({
    PairingProtocol? protocol,
    Future<List<String>> Function()? addressProvider,
  }) : _protocol = protocol ?? PairingProtocol(),
       _addressProvider = addressProvider;

  static const _maxBodyBytes = 8192;
  static const _page = r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>Connect to Immich TV</title>
  <style>
    :root { color-scheme: dark; font: 17px system-ui, sans-serif; background: #101019; color: #f8f7ff; }
    body { box-sizing: border-box; margin: 0 auto; max-width: 520px; padding: 32px 24px; }
    main { margin-top: 8vh; padding: 28px; border: 1px solid #454257; border-radius: 22px; background: #1b1a27; }
    h1 { font-size: 1.6rem; margin-top: 0; }
    p { line-height: 1.5; color: #cfccdc; }
    .code { font-size: 2rem; font-weight: 800; letter-spacing: .18em; color: #d4b7ff; }
    .status { margin-top: 24px; padding: 14px; border-radius: 12px; background: #292738; }
  </style>
</head>
<body>
  <main>
    <h1>Connect to Immich TV</h1>
    <p id="message" role="status">Checking this one-time pairing request…</p>
    <p id="code" class="code" aria-label="Verification code"></p>
    <p id="detail" class="status">Keep this page open while you approve the request on your TV.</p>
  </main>
  <script nonce="__NONCE__">
    (() => {
      const message = document.getElementById('message');
      const code = document.getElementById('code');
      const detail = document.getElementById('detail');
      const params = new URLSearchParams(location.hash.slice(1));
      const sessionId = params.get('session');
      const token = params.get('token');
      history.replaceState(null, '', location.pathname);
      if (!sessionId || !token) {
        message.textContent = 'This pairing link is incomplete. Scan the QR code again.';
        return;
      }
      const send = async (path, body) => {
        const response = await fetch(path, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          cache: 'no-store',
          credentials: 'omit',
          referrerPolicy: 'no-referrer',
          body: JSON.stringify(body)
        });
        if (!response.ok) throw new Error('request_failed');
        return response.json();
      };
      const waitForApproval = async () => {
        while (true) {
          await new Promise(resolve => setTimeout(resolve, 1200));
          const status = await send('/api/status', { sessionId });
          if (status.phase === 'active') {
            message.textContent = 'Immich TV approved this phone.';
            detail.textContent = 'Phone text entry is not enabled in this preview. Continue setup on your TV.';
            return;
          }
          if (status.phase === 'expired' || status.phase === 'revoked' || status.phase === 'stopped') {
            message.textContent = status.phase === 'expired'
              ? 'This pairing request expired. Start a new request on your TV.'
              : 'This pairing request was closed on your TV.';
            detail.textContent = 'You can close this page.';
            return;
          }
        }
      };
      send('/api/pair', { sessionId, bootstrapToken: token })
        .then(async result => {
          message.textContent = 'Compare this code with the code shown on your TV.';
          code.textContent = result.verificationCode;
          await waitForApproval();
        })
        .catch(() => {
          message.textContent = 'Could not reach the TV. Check that both devices are on the same network, then scan again.';
          detail.textContent = 'Guest Wi-Fi or router device isolation can block phone-to-TV connections.';
        });
    })();
  </script>
</body>
</html>''';

  final PairingProtocol _protocol;
  final Future<List<String>> Function()? _addressProvider;
  final StreamController<PairingSnapshot?> _updates =
      StreamController<PairingSnapshot?>.broadcast();
  HttpServer? _server;
  PairingSnapshot? _snapshot;
  List<String> _allowedHosts = const [];

  @override
  bool get isSupported => true;

  @override
  PairingSnapshot? get snapshot => _snapshot;

  @override
  Stream<PairingSnapshot?> get updates => _updates.stream;

  @override
  Future<PairingConnection> start() async {
    if (_server != null) {
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }

    final addresses =
        await (_addressProvider?.call() ?? _findPrivateIpv4Addresses());
    if (addresses.isEmpty) {
      throw const PairingServiceException(PairingServiceFailure.noLocalNetwork);
    }

    final invitation = _protocol.start();
    try {
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      _server = server;
      _allowedHosts = addresses;
      server.listen(_handleRequest, onError: (_) {});

      final manualUris = addresses
          .map(
            (address) => Uri(
              scheme: 'http',
              host: address,
              port: server.port,
              path: '/',
            ),
          )
          .toList(growable: false);
      final qrUri = Uri(
        scheme: 'http',
        host: addresses.first,
        port: server.port,
        path: '/',
        fragment: Uri(
          queryParameters: {
            'session': invitation.sessionId,
            'token': invitation.bootstrapToken,
          },
        ).query,
      );
      _publish(_protocol.snapshot);
      return PairingConnection(
        invitation: invitation,
        qrUri: qrUri,
        manualUris: manualUris,
      );
    } catch (_) {
      _protocol.stop();
      _server = null;
      _allowedHosts = const [];
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }
  }

  @override
  PairingSnapshot approve() {
    final sessionId = _snapshot?.sessionId;
    if (sessionId == null) {
      throw const PairingProtocolException(PairingFailure.noSession);
    }
    _protocol.approve(sessionId: sessionId);
    return _publish(_protocol.snapshot)!;
  }

  @override
  PairingSnapshot deny() {
    final sessionId = _snapshot?.sessionId;
    if (sessionId == null) {
      throw const PairingProtocolException(PairingFailure.noSession);
    }
    _protocol.deny(sessionId: sessionId);
    return _publish(_protocol.snapshot)!;
  }

  @override
  Future<void> stop() async {
    _protocol.stop();
    _publish(_protocol.snapshot);
    final server = _server;
    _server = null;
    _allowedHosts = const [];
    await server?.close(force: true);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _updates.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applySecurityHeaders(request.response);
    if (!_isAllowedHost(request)) {
      await _respond(request.response, HttpStatus.forbidden, {
        'error': 'forbidden',
      });
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/') {
      final nonce = _randomNonce();
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set(
        'content-security-policy',
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-$nonce'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      );
      request.response.write(_page.replaceFirst('__NONCE__', nonce));
      await request.response.close();
      return;
    }

    if (request.method != 'POST' ||
        (request.uri.path != '/api/pair' &&
            request.uri.path != '/api/status')) {
      await _respond(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
      return;
    }
    if (!_isSameOrigin(request)) {
      await _respond(request.response, HttpStatus.forbidden, {
        'error': 'origin',
      });
      return;
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      await _respond(request.response, HttpStatus.unsupportedMediaType, {
        'error': 'content_type',
      });
      return;
    }

    final Map<String, Object?> body;
    try {
      body = await _readJsonBody(request);
    } on Object {
      await _respond(request.response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }

    if (request.uri.path == '/api/pair') {
      await _handlePairRequest(request.response, body);
    } else {
      await _handleStatusRequest(request.response, body);
    }
  }

  Future<void> _handlePairRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final sessionId = body['sessionId'];
    final token = body['bootstrapToken'];
    if (sessionId is! String || token is! String) {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }
    try {
      final snapshot = _protocol.requestApproval(
        sessionId: sessionId,
        bootstrapToken: token,
      );
      _publish(snapshot);
      await _respond(response, HttpStatus.ok, {
        'phase': snapshot.phase.name,
        'verificationCode': snapshot.verificationCode,
      });
    } on PairingProtocolException catch (error) {
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    }
  }

  Future<void> _handleStatusRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final sessionId = body['sessionId'];
    final snapshot = _protocol.snapshot;
    if (sessionId is! String ||
        snapshot == null ||
        snapshot.sessionId != sessionId) {
      await _respond(response, HttpStatus.notFound, {
        'error': 'session_not_found',
      });
      return;
    }
    _publish(snapshot);
    await _respond(response, HttpStatus.ok, {'phase': snapshot.phase.name});
  }

  Future<Map<String, Object?>> _readJsonBody(HttpRequest request) async {
    if (request.contentLength > _maxBodyBytes) {
      throw const FormatException('Request too large.');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maxBodyBytes) {
        throw const FormatException('Request too large.');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  bool _isAllowedHost(HttpRequest request) {
    final host = request.headers.host;
    final port = _server?.port;
    if (host == null || port == null) return false;
    return request.connectionInfo?.localPort == port &&
        _allowedHosts.contains(host);
  }

  bool _isSameOrigin(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null) return false;
    final host = request.headers.host;
    final port = request.connectionInfo?.localPort;
    return host != null &&
        port != null &&
        origin == Uri(scheme: 'http', host: host, port: port).origin;
  }

  void _applySecurityHeaders(HttpResponse response) {
    response.headers
      ..set('x-content-type-options', 'nosniff')
      ..set('referrer-policy', 'no-referrer')
      ..set(HttpHeaders.cacheControlHeader, 'no-store, max-age=0')
      ..set('x-frame-options', 'DENY');
  }

  Future<void> _respond(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  PairingSnapshot? _publish(PairingSnapshot? snapshot) {
    _snapshot = snapshot;
    if (!_updates.isClosed) _updates.add(snapshot);
    return snapshot;
  }

  String _randomNonce() => base64Url
      .encode(List<int>.generate(18, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');

  Future<List<String>> _findPrivateIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address)) addresses.add(address.address);
      }
    }
    return addresses.toList(growable: false)..sort();
  }

  bool _isPrivateIpv4(InternetAddress address) {
    final parts = address.rawAddress;
    return parts.length == 4 &&
        (parts[0] == 10 ||
            (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
            (parts[0] == 192 && parts[1] == 168));
  }
}
