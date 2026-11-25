import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pairing_crypto.dart';
import 'pairing_protocol.dart';
import 'pairing_service.dart';
import 'phone_pairing_config.dart';

PhonePairingService createPhonePairingService() => IoPhonePairingService();

class IoPhonePairingService implements PhonePairingService {
  IoPhonePairingService({
    PairingProtocol? protocol,
    Future<List<String>> Function()? addressProvider,
    Uri? companionBaseUri,
    String? companionOrigin,
  }) : _protocol = protocol ?? PairingProtocol(),
       _addressProvider = addressProvider,
       _companionBaseUri =
           companionBaseUri ?? Uri.parse(PhonePairingConfig.companionUrl),
       _companionOrigin =
           companionOrigin ?? Uri.parse(PhonePairingConfig.companionUrl).origin;

  static const _maxBodyBytes = 24 * 1024;
  static const _apiPaths = {'/api/pair', '/api/status', '/api/input'};
  final PairingProtocol _protocol;
  final Future<List<String>> Function()? _addressProvider;
  final Uri _companionBaseUri;
  final String _companionOrigin;
  final StreamController<PairingSnapshot?> _updates =
      StreamController<PairingSnapshot?>.broadcast();
  final StreamController<PhoneOnboardingInput> _onboardingInputs =
      StreamController<PhoneOnboardingInput>.broadcast();
  HttpServer? _server;
  PairingSnapshot? _snapshot;
  List<String> _allowedHosts = const [];
  PairingCryptoHandshake? _cryptoHandshake;
  PairingCryptoSession? _cryptoSession;
  Timer? _expiryTimer;
  bool _pairRequestPending = false;

  @override
  bool get isSupported => true;

  @override
  PairingSnapshot? get snapshot => _snapshot;

  @override
  Stream<PairingSnapshot?> get updates => _updates.stream;

  @override
  Stream<PhoneOnboardingInput> get onboardingInputs => _onboardingInputs.stream;

  @override
  Future<PairingConnection> start() async {
    if (_server != null) {
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }

    _validateCompanionUri();
    _expiryTimer?.cancel();
    _destroyCrypto();
    final addresses =
        await (_addressProvider?.call() ?? _findPrivateIpv4Addresses());
    if (addresses.isEmpty) {
      throw const PairingServiceException(PairingServiceFailure.noLocalNetwork);
    }

    final invitation = _protocol.start();
    HttpServer? server;
    try {
      final handshake = await PairingCryptoSession.createForTv(
        sessionId: invitation.sessionId,
      );
      _cryptoHandshake = handshake;
      final boundServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      server = boundServer;
      _server = boundServer;
      _allowedHosts = addresses;
      boundServer.listen(_handleRequest, onError: (_) {});

      final manualUris = addresses
          .map((address) {
            final endpoint = Uri(
              scheme: 'http',
              host: address,
              port: boundServer.port,
            );
            final invite = {
              'v': PairingCryptoSession.protocolVersion,
              'sessionId': invitation.sessionId,
              'bootstrapToken': invitation.bootstrapToken,
              'endpoint': endpoint.origin,
              'tvPublicKey': PairingCryptoSession.encodeBytes(
                handshake.publicKeyBytes,
              ),
            };
            final fragment = PairingCryptoSession.encodeBytes(
              utf8.encode(jsonEncode(invite)),
            );
            return _companionBaseUri.replace(fragment: fragment);
          })
          .toList(growable: false);
      final qrUri = manualUris.first;
      _scheduleExpiry(invitation.expiresAt);
      _publish(_protocol.snapshot);
      return PairingConnection(
        invitation: invitation,
        qrUri: qrUri,
        manualUris: manualUris,
      );
    } catch (_) {
      _protocol.stop();
      _cryptoHandshake?.destroy();
      _cryptoHandshake = null;
      _server = null;
      _allowedHosts = const [];
      await server?.close(force: true);
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }
  }

  @override
  PairingSnapshot approve() {
    final sessionId = _snapshot?.sessionId;
    if (sessionId == null) {
      throw const PairingProtocolException(PairingFailure.noSession);
    }
    final cryptoSession = _cryptoSession;
    if (cryptoSession == null) {
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }
    final grant = _protocol.approve(
      sessionId: sessionId,
      sessionToken: PairingCryptoSession.encodeBytes(
        cryptoSession.sessionToken,
      ),
    );
    _scheduleExpiry(grant.expiresAt);
    return _publish(_protocol.snapshot)!;
  }

  @override
  PairingSnapshot deny() {
    final sessionId = _snapshot?.sessionId;
    if (sessionId == null) {
      throw const PairingProtocolException(PairingFailure.noSession);
    }
    _protocol.deny(sessionId: sessionId);
    _destroyCrypto();
    _expiryTimer?.cancel();
    return _publish(_protocol.snapshot)!;
  }

  @override
  Future<void> stop() async {
    _expiryTimer?.cancel();
    _protocol.stop();
    _publish(_protocol.snapshot);
    _destroyCrypto();
    final server = _server;
    _server = null;
    _allowedHosts = const [];
    await server?.close(force: true);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _updates.close();
    await _onboardingInputs.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applySecurityHeaders(request.response);
    if (!_isAllowedHost(request)) {
      await _respond(request.response, HttpStatus.forbidden, {
        'error': 'forbidden',
      });
      return;
    }
    if (!_isAllowedOrigin(request)) {
      await _respond(request.response, HttpStatus.forbidden, {
        'error': 'origin',
      });
      return;
    }
    _applyCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      if (!_apiPaths.contains(request.uri.path) ||
          request.uri.hasQuery ||
          request.headers.value('access-control-request-method') != 'POST' ||
          request.headers
                  .value('access-control-request-headers')
                  ?.toLowerCase() !=
              'content-type') {
        await _respond(request.response, HttpStatus.forbidden, {
          'error': 'preflight',
        });
        return;
      }
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }
    if (request.method != 'POST' ||
        !_apiPaths.contains(request.uri.path) ||
        request.uri.hasQuery) {
      await _respond(request.response, HttpStatus.notFound, {
        'error': 'not_found',
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

    switch (request.uri.path) {
      case '/api/pair':
        await _handlePairRequest(request.response, body);
      case '/api/status':
        await _handleStatusRequest(request.response, body);
      case '/api/input':
        await _handleInputRequest(request.response, body);
    }
  }

  Future<void> _handlePairRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final sessionId = body['sessionId'];
    final token = body['bootstrapToken'];
    final phonePublicKey = body['phonePublicKey'];
    if (body.length != 3 ||
        sessionId is! String ||
        token is! String ||
        phonePublicKey is! String) {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }
    if (_pairRequestPending) {
      await _respond(response, HttpStatus.conflict, {'error': 'pairing_busy'});
      return;
    }
    _pairRequestPending = true;
    PairingCryptoSession? cryptoSession;
    try {
      _protocol.verifyBootstrapToken(
        sessionId: sessionId,
        bootstrapToken: token,
      );
      final handshake = _cryptoHandshake;
      if (handshake == null || handshake.sessionId != sessionId) {
        await _respond(response, HttpStatus.conflict, {
          'error': 'pairing_unavailable',
        });
        return;
      }
      cryptoSession = await PairingCryptoSession.deriveForTv(
        sessionId: sessionId,
        tvHandshake: handshake,
        phonePublicKeyBytes: PairingCryptoSession.decodeBytes(phonePublicKey),
      );
      final code = await cryptoSession.approvalCode();
      final snapshot = _protocol.requestApproval(
        sessionId: sessionId,
        bootstrapToken: token,
        verificationCode: code,
      );
      _cryptoSession = cryptoSession;
      _cryptoHandshake = null;
      _publish(snapshot);
      await _respond(response, HttpStatus.ok, {'phase': snapshot.phase.name});
    } on PairingProtocolException catch (error) {
      if (cryptoSession != null) {
        _cryptoHandshake = null;
        cryptoSession.destroy();
      }
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    } on PairingCryptoException catch (error) {
      await _respond(response, HttpStatus.badRequest, {'error': error.code});
    } on Object {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } finally {
      _pairRequestPending = false;
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

  Future<void> _handleInputRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final PairingCryptoSession? cryptoSession = _cryptoSession;
    final sessionId = body['sessionId'];
    final sequence = body['seq'];
    if (cryptoSession == null ||
        sessionId is! String ||
        sessionId != cryptoSession.sessionId ||
        sequence is! int ||
        body['type'] != 'onboardingInput') {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }

    try {
      final sessionToken = PairingCryptoSession.encodeBytes(
        cryptoSession.sessionToken,
      );
      _protocol.requireActiveSession(
        sessionId: sessionId,
        sessionToken: sessionToken,
      );
      final message = EncryptedPairingMessage.fromJson(body);
      final plaintext = await cryptoSession.decryptFromPhone(message);
      _protocol.acceptSequence(
        sessionId: sessionId,
        sessionToken: sessionToken,
        sequence: sequence,
      );
      try {
        final decoded = jsonDecode(utf8.decode(plaintext));
        if (decoded is! Map<String, Object?>) {
          throw const PairingProtocolException(PairingFailure.invalidMessage);
        }
        final input = PhoneOnboardingInput.fromJson(decoded);
        if (!_onboardingInputs.isClosed) _onboardingInputs.add(input);
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }
      await _respond(response, HttpStatus.ok, {'accepted': true});
    } on PairingCryptoException catch (error) {
      await _respond(response, HttpStatus.badRequest, {'error': error.code});
    } on PairingProtocolException catch (error) {
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    } on FormatException {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } on Object {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    }
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
    final authority = request.headers.host;
    final port = _server?.port;
    if (authority == null || port == null) return false;
    final uri = Uri.tryParse('http://$authority');
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    // Some embedded HTTP clients omit the non-default port from Host. The
    // socket's local port is authoritative; keep the hostname allowlist exact.
    return request.connectionInfo?.localPort == port &&
        (uri.port == port || uri.port == 80) &&
        _allowedHosts.contains(uri.host);
  }

  bool _isAllowedOrigin(HttpRequest request) =>
      request.headers.value('origin') == _companionOrigin;

  void _applyCorsHeaders(HttpResponse response) {
    response.headers
      ..set('access-control-allow-origin', _companionOrigin)
      ..set('access-control-allow-methods', 'POST, OPTIONS')
      ..set('access-control-allow-headers', 'content-type')
      ..set('access-control-max-age', '120')
      ..set('vary', 'Origin');
  }

  void _applySecurityHeaders(HttpResponse response) {
    response.headers
      ..set('x-content-type-options', 'nosniff')
      ..set('referrer-policy', 'no-referrer')
      ..set(HttpHeaders.cacheControlHeader, 'no-store, max-age=0')
      ..set('x-frame-options', 'DENY');
  }

  void _validateCompanionUri() {
    if (_companionBaseUri.scheme != 'https' ||
        _companionBaseUri.host.isEmpty ||
        _companionBaseUri.userInfo.isNotEmpty ||
        _companionBaseUri.query.isNotEmpty ||
        _companionBaseUri.hasFragment ||
        _companionBaseUri.origin != _companionOrigin) {
      throw const PairingServiceException(
        PairingServiceFailure.companionUnavailable,
      );
    }
  }

  void _scheduleExpiry(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final delay = expiresAt.difference(DateTime.now());
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      final snapshot = _protocol.snapshot;
      _publish(snapshot);
      if (snapshot == null ||
          snapshot.phase == PairingPhase.expired ||
          snapshot.phase == PairingPhase.revoked) {
        _destroyCrypto();
        return;
      }
      _scheduleExpiry(snapshot.expiresAt);
    });
  }

  void _destroyCrypto() {
    _cryptoHandshake?.destroy();
    _cryptoHandshake = null;
    _cryptoSession?.destroy();
    _cryptoSession = null;
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
