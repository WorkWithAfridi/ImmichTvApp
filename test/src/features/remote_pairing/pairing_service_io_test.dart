import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_crypto.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service_io.dart';
import 'package:immichtv/src/features/remote_pairing/remote_command.dart';

void main() {
  late IoPhonePairingService service;
  final companionUri = Uri.parse('https://companion.test/phone/');

  setUp(() {
    service = IoPhonePairingService(
      addressProvider: () async => ['127.0.0.1'],
      companionBaseUri: companionUri,
      companionOrigin: companionUri.origin,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  test('pinned QR bootstraps encrypted setup only after TV approval', () async {
    final connection = await service.start();
    final client = HttpClient();
    addTearDown(client.close);
    expect(connection.qrUri.scheme, 'https');
    expect(connection.qrUri.origin, companionUri.origin);
    expect(connection.qrUri.query, isEmpty);

    final invitation =
        jsonDecode(
              utf8.decode(
                PairingCryptoSession.decodeBytes(connection.qrUri.fragment),
              ),
            )
            as Map<String, Object?>;
    expect(invitation['endpoint'], startsWith('http://127.0.0.1:'));
    expect(invitation, contains('tvPublicKey'));

    final pageRequest = await client.getUrl(
      Uri.parse('${invitation['endpoint']}/'),
    );
    pageRequest.headers.set('Origin', companionUri.origin);
    final pageResponse = await pageRequest.close();
    expect(pageResponse.statusCode, HttpStatus.notFound);
    await pageResponse.drain<void>();

    final preflightRequest = await client.openUrl(
      'OPTIONS',
      Uri.parse('${invitation['endpoint']}/api/pair'),
    );
    preflightRequest.headers
      ..set('Origin', companionUri.origin)
      ..set('Access-Control-Request-Method', 'POST')
      ..set('Access-Control-Request-Headers', 'content-type');
    final preflight = await preflightRequest.close();
    expect(preflight.statusCode, HttpStatus.noContent);
    expect(
      preflight.headers.value('access-control-allow-origin'),
      companionUri.origin,
    );
    expect(preflight.headers.value('access-control-allow-origin'), isNot('*'));
    await preflight.drain<void>();

    final phone = await PairingCryptoSession.createForPhone(
      sessionId: invitation['sessionId']! as String,
      tvPublicKeyBytes: PairingCryptoSession.decodeBytes(
        invitation['tvPublicKey']! as String,
      ),
    );
    addTearDown(phone.destroy);
    final pairResponse = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/pair',
      {
        'sessionId': invitation['sessionId'],
        'bootstrapToken': invitation['bootstrapToken'],
        'phonePublicKey': PairingCryptoSession.encodeBytes(
          phone.publicKeyBytes,
        ),
      },
      origin: companionUri.origin,
    );
    expect(pairResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(await utf8.decoder.bind(pairResponse).join()), {
      'phase': PairingPhase.approvalPending.name,
    });
    expect(service.snapshot?.verificationCode, await phone.approvalCode());

    final received = Completer<PhoneOnboardingInput>();
    final subscription = service.onboardingInputs.listen(received.complete);
    addTearDown(subscription.cancel);
    service.approve();

    final statusResponse = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/status',
      {'sessionId': invitation['sessionId']},
      origin: companionUri.origin,
    );
    expect(statusResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(await utf8.decoder.bind(statusResponse).join()), {
      'phase': PairingPhase.active.name,
    });

    const input = PhoneOnboardingInput.apiKey(
      serverUrl: 'https://photos.example.com',
      apiKey: 'key-with!punctuation',
    );
    final encrypted = await phone.encryptToTv(
      type: 'onboardingInput',
      plaintext: utf8.encode(jsonEncode(input.toJson())),
    );
    final inputResponse = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/input',
      encrypted.toJson(),
      origin: companionUri.origin,
    );
    expect(inputResponse.statusCode, HttpStatus.ok);
    expect(jsonDecode(await utf8.decoder.bind(inputResponse).join()), {
      'accepted': true,
    });
    final receivedInput = await received.future.timeout(
      const Duration(seconds: 1),
    );
    expect(receivedInput.apiKey, input.apiKey);
    expect(receivedInput.serverUrl, input.serverUrl);
    expect(receivedInput.toString(), isNot(contains(input.apiKey)));

    final tampered = await phone.encryptToTv(
      type: 'onboardingInput',
      plaintext: utf8.encode(jsonEncode(input.toJson())),
    );
    final tamperedJson = tampered.toJson();
    final tag = tamperedJson['tag']! as String;
    tamperedJson['tag'] =
        '${tag.substring(0, tag.length - 1)}${tag.endsWith('A') ? 'B' : 'A'}';
    final rejected = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/input',
      tamperedJson,
      origin: companionUri.origin,
    );
    expect(rejected.statusCode, HttpStatus.badRequest);
    await rejected.drain<void>();
    expect(service.snapshot?.phase, PairingPhase.revoked);
  });

  test('rejects cross-origin requests before pairing state changes', () async {
    final connection = await service.start();
    final client = HttpClient();
    addTearDown(client.close);
    final invitation =
        jsonDecode(
              utf8.decode(
                PairingCryptoSession.decodeBytes(connection.qrUri.fragment),
              ),
            )
            as Map<String, Object?>;
    final otherPhoneKeyPair = await X25519().newKeyPair();
    final otherPhonePublicKey = await otherPhoneKeyPair.extractPublicKey();
    final response = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/pair',
      {
        'sessionId': invitation['sessionId'],
        'bootstrapToken': invitation['bootstrapToken'],
        'phonePublicKey': PairingCryptoSession.encodeBytes(
          otherPhonePublicKey.bytes,
        ),
      },
      origin: 'https://attacker.example',
    );
    expect(response.statusCode, HttpStatus.forbidden);
    expect(service.snapshot?.phase, PairingPhase.waitingForPhone);
    await response.drain<void>();
  });

  test('delivers encrypted remote commands and acknowledges them', () async {
    final connection = await service.start(mode: PhonePairingMode.remote);
    expect(connection.mode, PhonePairingMode.remote);
    final client = HttpClient();
    addTearDown(client.close);
    final invitation =
        jsonDecode(
             utf8.decode(
               PairingCryptoSession.decodeBytes(connection.qrUri.fragment),
             ),
           )
           as Map<String, Object?>;
    expect(invitation['mode'], 'remote');

    // No command may execute before an approved session exists.
    final tooEarly = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/command',
      {
        'v': 1,
        'type': 'remoteCommand',
        'sessionId': invitation['sessionId'],
        'seq': 1,
        'nonce': 'AAAAAAAAAAAAAAAAAAAAAA',
        'ciphertext': 'AAAA',
        'tag': 'AAAAAAAAAAAAAAAAAAAAAA',
      },
      origin: companionUri.origin,
    );
    expect(tooEarly.statusCode, HttpStatus.forbidden);
    await tooEarly.drain<void>();

    final phone = await PairingCryptoSession.createForPhone(
      sessionId: invitation['sessionId']! as String,
      tvPublicKeyBytes: PairingCryptoSession.decodeBytes(
        invitation['tvPublicKey']! as String,
      ),
    );
    addTearDown(phone.destroy);
    final pairResponse = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/pair',
      {
        'sessionId': invitation['sessionId'],
        'bootstrapToken': invitation['bootstrapToken'],
        'phonePublicKey': PairingCryptoSession.encodeBytes(
          phone.publicKeyBytes,
        ),
      },
      origin: companionUri.origin,
    );
    expect(pairResponse.statusCode, HttpStatus.ok);
    await pairResponse.drain<void>();
    service.approve();

    final delivered = <RemoteCommand>[];
    final subscription = service.remoteCommands.listen((request) {
      delivered.add(request.command);
      service.resolveRemoteCommand(request, RemoteCommandOutcome.ok);
    });
    addTearDown(subscription.cancel);

    final command = RemoteCommand.fromJson({
      'v': 1,
      'type': 'remoteCommand',
      'seq': 1,
      'command': 'navigate',
      'direction': 'down',
    });
    final encrypted = await phone.encryptToTv(
      type: 'remoteCommand',
      plaintext: utf8.encode(jsonEncode(command.toJson())),
    );
    final response = await _post(
      client,
      Uri.parse(invitation['endpoint']! as String),
      '/api/command',
      encrypted.toJson(),
      origin: companionUri.origin,
    );
    expect(response.statusCode, HttpStatus.ok);
    final ackBody =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, Object?>;
    final ack = EncryptedPairingMessage.fromJson(ackBody);
    expect(ack.type, 'ack');
    final plaintext = await phone.decryptFromTv(ack);
    final decoded = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    expect(decoded, {
      'v': 1,
      'type': 'ack',
      'seq': 1,
      'accepted': true,
      'outcome': 'ok',
    });
    expect(delivered.single.type, RemoteCommandType.navigate);
    expect(delivered.single.direction, RemoteDirection.down);
  });

  test('self-hosted mode connects on scan and allows multiple controllers', () async {
    final localService = IoPhonePairingService(
      addressProvider: () async => ['127.0.0.1'],
      selfHostedCompanion: true,
      assetLoader: (name) async => utf8.encode('<asset>$name</asset>'),
    );
    addTearDown(localService.dispose);

    final connection = await localService.start();
    expect(connection.qrUri.scheme, 'http');
    expect(connection.qrUri.path, '/');
    final invitation =
        jsonDecode(
              utf8.decode(
                PairingCryptoSession.decodeBytes(connection.qrUri.fragment),
              ),
            )
            as Map<String, Object?>;
    expect(invitation, isNot(contains('tvPublicKey')));
    expect(invitation, isNot(contains('bootstrapToken')));
    final endpoint = Uri.parse(invitation['endpoint']! as String);
    final sessionId = invitation['sessionId']! as String;

    final client = HttpClient();
    addTearDown(client.close);
    final pageRequest = await client.getUrl(endpoint);
    final pageResponse = await pageRequest.close();
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(pageResponse).join(), '<asset>index.html</asset>');

    Future<Map<String, Object?>> connect() async {
      final response = await _post(client, endpoint, '/api/pair', {
        'sessionId': sessionId,
      });
      expect(response.statusCode, HttpStatus.ok);
      return jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, Object?>;
    }

    final first = await connect();
    // Reusing the active session lets another phone scan the same QR.
    final reused = await localService.start();
    expect(reused.qrUri, connection.qrUri);
    final second = await connect();
    expect(first['phase'], PairingPhase.active.name);
    final firstToken = first['sessionToken']! as String;
    final secondToken = second['sessionToken']! as String;
    expect(secondToken, isNot(firstToken));
    expect(second['clients'], 2);

    final statusResponse = await _post(client, endpoint, '/api/status', {
      'sessionId': sessionId,
      'sessionToken': firstToken,
    });
    expect(
      jsonDecode(await utf8.decoder.bind(statusResponse).join()),
      containsPair('phase', PairingPhase.active.name),
    );

    final received = Completer<PhoneOnboardingInput>();
    final subscription = localService.onboardingInputs.listen(received.complete);
    addTearDown(subscription.cancel);
    final inputResponse = await _post(client, endpoint, '/api/input', {
      'sessionId': sessionId,
      'sessionToken': firstToken,
      'seq': 1,
      'v': 1,
      'type': 'onboardingInput',
      'serverUrl': 'https://photos.example.com',
      'authMethod': 'apiKey',
      'apiKey': 'local-key',
    });
    expect(inputResponse.statusCode, HttpStatus.ok);
    expect((await received.future).apiKey, 'local-key');

    final delivered = <RemoteCommand>[];
    final commandSubscription = localService.remoteCommands.listen((request) {
      delivered.add(request.command);
      localService.resolveRemoteCommand(request, RemoteCommandOutcome.ok);
    });
    addTearDown(commandSubscription.cancel);
    for (final (token, sequence) in [
      (firstToken, 2),
      (secondToken, 1),
      (firstToken, 3),
    ]) {
      final commandResponse = await _post(client, endpoint, '/api/command', {
        'sessionId': sessionId,
        'sessionToken': token,
        'v': 1,
        'type': 'remoteCommand',
        'seq': sequence,
        'command': 'select',
      });
      final ackBody = await utf8.decoder.bind(commandResponse).join();
      final ack = jsonDecode(ackBody) as Map<String, Object?>;
      expect(
        ack['accepted'],
        isTrue,
        reason: 'command $sequence for ${token.substring(0, 6)} returned $ackBody',
      );
    }
    expect(delivered, hasLength(3));
    expect(delivered.every((command) => command.type == RemoteCommandType.select), isTrue);
  });
}

Future<HttpClientResponse> _post(
  HttpClient client,
  Uri base,
  String path,
  Map<String, Object?> body, {
  String? origin,
}) async {
  final request = await client.postUrl(base.resolve(path));
  request.headers.contentType = ContentType.json;
  request.headers.set('Origin', origin ?? 'https://companion.test');
  request.write(jsonEncode(body));
  return request.close();
}
