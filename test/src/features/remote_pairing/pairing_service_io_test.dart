import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_crypto.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_service_io.dart';

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
    final otherPhonePublicKey =
        await otherPhoneKeyPair.extractPublicKey() as SimplePublicKey;
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
