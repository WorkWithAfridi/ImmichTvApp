import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'pairing_crypto.dart';
import 'pairing_protocol.dart';
import 'pairing_service.dart';
import 'phone_pairing_config.dart';
import 'remote_command.dart';

/// The TV hosts the companion page on its own LAN address. The phone loads the
/// page directly from the TV and talks to that same origin, so no external web
/// host is involved.
PhonePairingService createPhonePairingService() =>
    IoPhonePairingService(selfHostedCompanion: true);

/// One phone that connected to the TV-hosted companion. Each device keeps its
/// own command sequence so several phones can control the TV at once.
class _LocalClient {
  final RemoteCommandSequence commands = RemoteCommandSequence();
  int lastInputSequence = 0;
}

class IoPhonePairingService implements PhonePairingService {
  IoPhonePairingService({
    PairingProtocol? protocol,
    Future<List<String>> Function()? addressProvider,
    Uri? companionBaseUri,
    String? companionOrigin,
    this.selfHostedCompanion = false,
    this.assetLoader,
  }) : _protocol = protocol ?? PairingProtocol(),
        _addressProvider = addressProvider,
        _companionBaseUri =
            companionBaseUri ?? Uri.parse(PhonePairingConfig.companionUrl),
        _companionOrigin =
            companionOrigin ?? Uri.parse(PhonePairingConfig.companionUrl).origin;

  /// When true the TV serves the companion assets itself over plain HTTP and
  /// uses the local-only plaintext transport instead of the external HTTPS
  /// companion flow.
  final bool selfHostedCompanion;

  /// Injectable for tests; defaults to the bundled Flutter assets.
  final Future<List<int>> Function(String name)? assetLoader;

  static final _companionAssetTypes = <String, ContentType>{
    'index.html': ContentType('text', 'html', charset: 'utf-8'),
    'app.js': ContentType('text', 'javascript', charset: 'utf-8'),
    'styles.css': ContentType('text', 'css', charset: 'utf-8'),
    'crypto.js': ContentType('text', 'javascript', charset: 'utf-8'),
    'commands.js': ContentType('text', 'javascript', charset: 'utf-8'),
    'plain.js': ContentType('text', 'javascript', charset: 'utf-8'),
  };

  static const _maxBodyBytes = 24 * 1024;
  static const _apiPaths = {
    '/api/pair',
    '/api/status',
    '/api/input',
    '/api/command',
    '/api/disconnect',
  };
  static const _maxCommandsPerWindow = 60;
  static const _commandWindow = Duration(seconds: 10);
  static const _commandResolutionTimeout = Duration(seconds: 3);

  final PairingProtocol _protocol;
  final Future<List<String>> Function()? _addressProvider;
  final Uri _companionBaseUri;
  final String _companionOrigin;
  final StreamController<PairingSnapshot?> _updates =
      StreamController<PairingSnapshot?>.broadcast();
  final StreamController<PhoneOnboardingInput> _onboardingInputs =
      StreamController<PhoneOnboardingInput>.broadcast();
  final StreamController<RemoteCommandRequest> _remoteCommands =
      StreamController<RemoteCommandRequest>.broadcast();
  final Map<String, RemoteCommandRequest> _pendingCommands = {};
  HttpServer? _server;
  PairingSnapshot? _snapshot;
  List<String> _allowedHosts = const [];
  PairingCryptoHandshake? _cryptoHandshake;
  PairingCryptoSession? _cryptoSession;
  final Map<String, _LocalClient> _localClients = {};
  String? _selfHostedBootstrapToken;
  PairingConnection? _activeConnection;
  Timer? _expiryTimer;
  bool _pairRequestPending = false;
  int _commandWindowCount = 0;
  DateTime _commandWindowStart = DateTime.fromMillisecondsSinceEpoch(0);
  int _nextCommandId = 0;

  @override
  bool get isSupported => true;

  @override
  PairingSnapshot? get snapshot => _snapshot;

  @override
  Stream<PairingSnapshot?> get updates => _updates.stream;

  @override
  Stream<PhoneOnboardingInput> get onboardingInputs => _onboardingInputs.stream;

  @override
  Stream<RemoteCommandRequest> get remoteCommands => _remoteCommands.stream;

  @override
  Future<PairingConnection> start({
    PhonePairingMode mode = PhonePairingMode.setup,
  }) async {
    if (_server != null) {
      // A TV-hosted session can serve any number of phones. Reuse its QR for
      // "pair another phone" instead of failing because the port is in use.
      final active = _activeConnection;
      if (selfHostedCompanion &&
          active != null &&
          _snapshot?.phase == PairingPhase.active) {
        return active;
      }
      throw const PairingServiceException(PairingServiceFailure.listenerFailed);
    }

    if (!selfHostedCompanion) {
      _validateCompanionUri();
    }
    _expiryTimer?.cancel();
    _destroyCrypto();
    _localClients.clear();
    final addresses =
        await (_addressProvider?.call() ?? _findPrivateIpv4Addresses());
    if (addresses.isEmpty) {
      throw const PairingServiceException(PairingServiceFailure.noLocalNetwork);
    }

    final invitation = _protocol.start();
    _selfHostedBootstrapToken = invitation.bootstrapToken;
    _resetCommandBudget();
    HttpServer? server;
    try {
      if (!selfHostedCompanion) {
        final handshake = await PairingCryptoSession.createForTv(
          sessionId: invitation.sessionId,
        );
        _cryptoHandshake = handshake;
      }
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
            final invite = <String, Object?>{
              'v': PairingCryptoSession.protocolVersion,
              'sessionId': invitation.sessionId,
              if (!selfHostedCompanion) 'bootstrapToken': invitation.bootstrapToken,
              'endpoint': endpoint.origin,
              if (!selfHostedCompanion)
                'tvPublicKey': PairingCryptoSession.encodeBytes(
                  _cryptoHandshake!.publicKeyBytes,
                ),
              'mode': mode.name,
            };
            final fragment = PairingCryptoSession.encodeBytes(
              utf8.encode(jsonEncode(invite)),
            );
            final base = selfHostedCompanion
                ? Uri(
                    scheme: 'http',
                    host: address,
                    port: boundServer.port,
                    path: '/',
                  )
                : _companionBaseUri;
            return base.replace(fragment: fragment);
          })
          .toList(growable: false);
      final qrUri = manualUris.first;
      if (!selfHostedCompanion) {
        _scheduleExpiry(invitation.expiresAt);
      }
      _publish(_protocol.snapshot);
      _activeConnection = PairingConnection(
        invitation: invitation,
        qrUri: qrUri,
        manualUris: manualUris,
        mode: mode,
      );
      return _activeConnection!;
    } catch (_) {
      _protocol.stop();
      _cryptoHandshake?.destroy();
      _cryptoHandshake = null;
      _server = null;
      _activeConnection = null;
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
    if (selfHostedCompanion) {
      // Already approved when the server started; nothing to do on TV.
      return _publish(_protocol.snapshot)!;
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
    _localClients.clear();
    _destroyCrypto();
    _expiryTimer?.cancel();
    return _publish(_protocol.snapshot)!;
  }

  @override
  void resolveRemoteCommand(
    RemoteCommandRequest request,
    RemoteCommandOutcome outcome,
  ) {
    if (!identical(_pendingCommands[request.id], request)) return;
    _pendingCommands.remove(request.id);
    request.complete(outcome);
  }

  @override
  Future<void> stop() async {
    _expiryTimer?.cancel();
    _protocol.stop();
    _publish(_protocol.snapshot);
    _localClients.clear();
    _destroyCrypto();
    _completePendingCommands(RemoteCommandOutcome.unavailable);
    final server = _server;
    _server = null;
    _activeConnection = null;
    _allowedHosts = const [];
    await server?.close(force: true);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _updates.close();
    await _onboardingInputs.close();
    await _remoteCommands.close();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _applySecurityHeaders(request.response);
    if (!_isAllowedHost(request)) {
      await _respond(request.response, HttpStatus.forbidden, {
        'error': 'forbidden',
      });
      return;
    }

    if (selfHostedCompanion) {
      // The page and the API share one origin, so no CORS or Origin check is
      // needed. GET requests serve the bundled companion files.
      if (request.method == 'GET' && !request.uri.hasQuery) {
        await _serveCompanionAsset(request);
        return;
      }
    } else {
      if (!_isAllowedOrigin(request)) {
        await _respond(request.response, HttpStatus.forbidden, {
          'error': 'origin',
        });
        return;
      }
      _applyCorsHeaders(request.response);
    }

    if (request.method == 'OPTIONS') {
      if (selfHostedCompanion) {
        await _respond(request.response, HttpStatus.notFound, {
          'error': 'not_found',
        });
        return;
      }
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

    if (selfHostedCompanion) {
      switch (request.uri.path) {
        case '/api/pair':
          await _handlePlainPairRequest(request.response, body);
        case '/api/status':
          await _handlePlainStatusRequest(request.response, body);
        case '/api/input':
          await _handlePlainInputRequest(request.response, body);
        case '/api/command':
          await _handlePlainCommandRequest(request.response, body);
        case '/api/disconnect':
          await _handlePlainDisconnectRequest(request.response, body);
      }
      return;
    }

    switch (request.uri.path) {
      case '/api/pair':
        await _handlePairRequest(request.response, body);
      case '/api/status':
        await _handleStatusRequest(request.response, body);
      case '/api/input':
        await _handleInputRequest(request.response, body);
      case '/api/command':
        await _handleCommandRequest(request.response, body);
    }
  }

  Future<void> _serveCompanionAsset(HttpRequest request) async {
    final path = request.uri.path;
    final name = path == '/' || path == '/index.html'
        ? 'index.html'
        : path.startsWith('/')
        ? path.substring(1)
        : '';
    final contentType = _companionAssetTypes[name];
    if (contentType == null) {
      await _respond(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
      return;
    }
    try {
      final loader = assetLoader;
      final bytes = loader != null
          ? await loader(name)
          : await _loadBundledAsset(name);
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = contentType;
      request.response.add(bytes);
      await request.response.close();
    } on Object {
      await _respond(request.response, HttpStatus.notFound, {
        'error': 'not_found',
      });
    }
  }

  Future<List<int>> _loadBundledAsset(String name) async {
    final data = await rootBundle.load('phone_companion/$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<void> _handlePlainPairRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    // Scanning the QR connects immediately. Every phone gets its own token and
    // sequence counter, so several devices can control the TV at the same time.
    final sessionId = body['sessionId'];
    final snapshot = _protocol.snapshot;
    if (body.length != 1 ||
        sessionId is! String ||
        snapshot == null ||
        snapshot.sessionId != sessionId ||
        (snapshot.phase != PairingPhase.waitingForPhone &&
            snapshot.phase != PairingPhase.active)) {
      await _respond(response, HttpStatus.forbidden, {
        'error': 'connect_unavailable',
      });
      return;
    }
    final token = base64Url
        .encode(SecurePairingEntropy().bytes(32))
        .replaceAll('=', '');
    _localClients[token] = _LocalClient();
    if (snapshot.phase == PairingPhase.waitingForPhone) {
      // First scan activates the session. There is no TV-side approval step.
      _protocol.requestApproval(
        sessionId: sessionId,
        bootstrapToken: _selfHostedBootstrapToken ?? '',
      );
      _protocol.approve(sessionId: sessionId);
      _publish(_protocol.snapshot);
    }
    await _respond(response, HttpStatus.ok, {
      'phase': PairingPhase.active.name,
      'sessionToken': token,
      'clients': _localClients.length,
    });
  }

  Future<void> _handlePlainDisconnectRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final token = body['sessionToken'];
    if (token is! String || !_localClients.containsKey(token)) {
      await _respond(response, HttpStatus.notFound, {
        'error': 'session_not_found',
      });
      return;
    }
    _localClients.remove(token);
    await _respond(response, HttpStatus.ok, {
      'disconnected': true,
      'clients': _localClients.length,
    });
  }

  Future<void> _handlePlainStatusRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final sessionId = body['sessionId'];
    final token = body['sessionToken'];
    final snapshot = _protocol.snapshot;
    if (sessionId is! String ||
        token is! String ||
        snapshot == null ||
        snapshot.sessionId != sessionId ||
        !_localClients.containsKey(token)) {
      await _respond(response, HttpStatus.forbidden, {
        'error': 'session_not_found',
      });
      return;
    }
    await _respond(response, HttpStatus.ok, {
      'phase': PairingPhase.active.name,
      'clients': _localClients.length,
    });
  }

  Future<void> _handlePlainInputRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final token = body['sessionToken'];
    final sequence = body['seq'];
    final client = token is String ? _localClients[token] : null;
    if (client == null || sequence is! int || sequence <= client.lastInputSequence) {
      await _respond(response, HttpStatus.forbidden, {
        'error': 'invalid_message',
      });
      return;
    }
    try {
      final payload = Map<String, Object?>.from(body)
        ..remove('sessionId')
        ..remove('sessionToken')
        ..remove('seq');
      final input = PhoneOnboardingInput.fromJson(payload);
      client.lastInputSequence = sequence;
      // The companion shares one sequence counter between setup input and
      // remote commands. Keep the command watermark in step so the first
      // command after a successful setup is not rejected as a sequence gap.
      client.commands.advanceTo(sequence);
      if (!_onboardingInputs.isClosed) _onboardingInputs.add(input);
      await _respond(response, HttpStatus.ok, {'accepted': true});
    } on PairingProtocolException catch (error) {
      await _respond(response, HttpStatus.badRequest, {
        'error': error.failure.name,
      });
    } on Object {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    }
  }

  Future<void> _handlePlainCommandRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final sessionId = _snapshot?.sessionId ?? '';
    final token = body['sessionToken'];
    final client = token is String ? _localClients[token] : null;
    if (client == null || _protocol.snapshot?.phase != PairingPhase.active) {
      await _respond(response, HttpStatus.forbidden, {
        'error': 'no_active_session',
      });
      return;
    }

    RemoteCommandRequest? request;
    try {
      if (_isRateLimited()) {
        await _respond(response, HttpStatus.tooManyRequests, {
          'error': 'rate_limited',
        });
        return;
      }
      final payload = Map<String, Object?>.from(body)
        ..remove('sessionId')
        ..remove('sessionToken');
      final command = RemoteCommand.fromJson(payload);
      client.commands.accept(command);
      request = RemoteCommandRequest(
        id: '$sessionId:${_nextCommandId++}',
        sessionId: sessionId,
        command: command,
      );
      _pendingCommands[request.id] = request;
      if (!_remoteCommands.isClosed) _remoteCommands.add(request);
      final outcome = await request.outcome.timeout(
        _commandResolutionTimeout,
        onTimeout: () => RemoteCommandOutcome.unavailable,
      );
      final ack = RemoteCommandAck(
        sequence: command.sequence,
        accepted: outcome == RemoteCommandOutcome.ok,
        outcome: outcome,
      );
      if (command.type == RemoteCommandType.disconnect) {
        _localClients.remove(token);
        await _respond(response, HttpStatus.ok, ack.toJson());
        return;
      }
      await _respond(response, HttpStatus.ok, ack.toJson());
    } on PairingProtocolException catch (error) {
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    } on RemoteCommandException catch (error) {
      await _respond(response, HttpStatus.badRequest, {
        'error': error.failure.name,
      });
    } on Object {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } finally {
      if (request != null) _pendingCommands.remove(request.id);
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
    if (cryptoSession == null) {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }
    if (sessionId is! String || sessionId != cryptoSession.sessionId) {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }
    if (sequence is! int || body['type'] != 'onboardingInput') {
      _revokeCryptoSession();
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
      // Publish the advanced sequence so a controller that continues this
      // session as a remote does not reject the next command as a gap.
      _publish(_protocol.snapshot);
      await _respond(response, HttpStatus.ok, {'accepted': true});
    } on PairingCryptoException catch (error) {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {'error': error.code});
    } on PairingProtocolException catch (error) {
      if (error.failure == PairingFailure.invalidMessage ||
          error.failure == PairingFailure.invalidSequence ||
          error.failure == PairingFailure.replayedMessage) {
        _revokeCryptoSession();
      }
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    } on FormatException {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } on Object {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    }
  }

  Future<void> _handleCommandRequest(
    HttpResponse response,
    Map<String, Object?> body,
  ) async {
    final cryptoSession = _cryptoSession;
    final snapshot = _protocol.snapshot;
    if (cryptoSession == null ||
        snapshot == null ||
        snapshot.phase != PairingPhase.active) {
      await _respond(response, HttpStatus.forbidden, {
        'error': 'no_active_session',
      });
      return;
    }
    final sessionId = body['sessionId'];
    if (sessionId is! String || sessionId != cryptoSession.sessionId) {
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }
    if (body['type'] != 'remoteCommand' || body['seq'] is! int) {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
      return;
    }

    RemoteCommandRequest? request;
    try {
      if (_isRateLimited()) {
        await _respond(response, HttpStatus.tooManyRequests, {
          'error': 'rate_limited',
        });
        return;
      }
      final sessionToken = PairingCryptoSession.encodeBytes(
        cryptoSession.sessionToken,
      );
      final message = EncryptedPairingMessage.fromJson(body);
      final plaintext = await cryptoSession.decryptFromPhone(message);
      try {
        _protocol.requireActiveSession(
          sessionId: sessionId,
          sessionToken: sessionToken,
        );
        _protocol.acceptSequence(
          sessionId: sessionId,
          sessionToken: sessionToken,
          sequence: message.sequence,
        );
        final decoded = jsonDecode(utf8.decode(plaintext));
        if (decoded is! Map<String, Object?>) {
          throw const PairingProtocolException(PairingFailure.invalidMessage);
        }
        final command = RemoteCommand.fromJson(decoded);
        if (command.sequence != message.sequence) {
          throw const PairingProtocolException(PairingFailure.invalidMessage);
        }
        request = RemoteCommandRequest(
          id: '$sessionId:${_nextCommandId++}',
          sessionId: sessionId,
          command: command,
        );
        _pendingCommands[request.id] = request;
        if (!_remoteCommands.isClosed) _remoteCommands.add(request);
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
      }

      final outcome = await request.outcome.timeout(
        _commandResolutionTimeout,
        onTimeout: () => RemoteCommandOutcome.unavailable,
      );
      final ack = RemoteCommandAck(
        sequence: request.command.sequence,
        accepted: outcome == RemoteCommandOutcome.ok,
        outcome: outcome,
      );
      final encrypted = await cryptoSession.encryptToPhone(
        type: 'ack',
        plaintext: utf8.encode(jsonEncode(ack.toJson())),
      );
      await _respond(response, HttpStatus.ok, encrypted.toJson());
      if (request.command.type == RemoteCommandType.disconnect) {
        await stop();
      }
    } on PairingCryptoException catch (error) {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {'error': error.code});
    } on PairingProtocolException catch (error) {
      if (error.failure == PairingFailure.invalidMessage ||
          error.failure == PairingFailure.invalidSequence ||
          error.failure == PairingFailure.replayedMessage ||
          error.failure == PairingFailure.invalidCredential) {
        _revokeCryptoSession();
      }
      final status = error.failure == PairingFailure.rateLimited
          ? HttpStatus.tooManyRequests
          : HttpStatus.forbidden;
      await _respond(response, status, {'error': error.failure.name});
    } on RemoteCommandException catch (error) {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': error.failure.name,
      });
    } on FormatException {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } on Object {
      _revokeCryptoSession();
      await _respond(response, HttpStatus.badRequest, {
        'error': 'invalid_message',
      });
    } finally {
      if (request != null) _pendingCommands.remove(request.id);
    }
  }

  bool _isRateLimited() {
    final now = DateTime.now();
    if (now.difference(_commandWindowStart) >= _commandWindow) {
      _resetCommandBudget();
    }
    _commandWindowCount++;
    return _commandWindowCount > _maxCommandsPerWindow;
  }

  void _resetCommandBudget() {
    _commandWindowCount = 0;
    _commandWindowStart = DateTime.now();
  }

  void _completePendingCommands(RemoteCommandOutcome outcome) {
    final pending = _pendingCommands.values.toList(growable: false);
    _pendingCommands.clear();
    for (final request in pending) {
      request.complete(outcome);
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
        _completePendingCommands(RemoteCommandOutcome.unavailable);
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

  void _revokeCryptoSession() {
    final sessionId = _cryptoSession?.sessionId;
    if (sessionId != null) {
      try {
        _protocol.revoke(sessionId: sessionId);
      } on PairingProtocolException {
        // Expiry or shutdown can race a malformed request; still clear keys.
      }
    }
    _expiryTimer?.cancel();
    _localClients.clear();
    _destroyCrypto();
    _completePendingCommands(RemoteCommandOutcome.invalid);
    _publish(_protocol.snapshot);
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
