import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_crypto.dart';

void main() {
  test(
    'TV and phone derive matching keys and decrypt an authenticated payload',
    () async {
      const sessionId = 'pairing-session-for-test';
      final tvHandshake = await PairingCryptoSession.createForTv(
        sessionId: sessionId,
      );
      final phone = await PairingCryptoSession.createForPhone(
        sessionId: sessionId,
        tvPublicKeyBytes: tvHandshake.publicKeyBytes,
      );
      final tv = await PairingCryptoSession.deriveForTv(
        sessionId: sessionId,
        tvHandshake: tvHandshake,
        phonePublicKeyBytes: phone.publicKeyBytes,
      );
      addTearDown(() {
        tvHandshake.destroy();
        phone.destroy();
        tv.destroy();
      });

      expect(await phone.approvalCode(), await tv.approvalCode());
      expect(phone.sessionToken, orderedEquals(tv.sessionToken));

      final plaintext = utf8.encode(
        '{"type":"onboardingInput","email":"test@example.com"}',
      );
      final encrypted = await phone.encryptToTv(
        type: 'onboardingInput',
        plaintext: plaintext,
      );
      final wireMessage = EncryptedPairingMessage.fromJson(encrypted.toJson());
      expect(await tv.decryptFromPhone(wireMessage), orderedEquals(plaintext));
    },
  );

  test(
    'rejects changed ciphertext, associated data, and replayed sequence',
    () async {
      const sessionId = 'tamper-test-session';
      final tvHandshake = await PairingCryptoSession.createForTv(
        sessionId: sessionId,
      );
      final phone = await PairingCryptoSession.createForPhone(
        sessionId: sessionId,
        tvPublicKeyBytes: tvHandshake.publicKeyBytes,
      );
      final tv = await PairingCryptoSession.deriveForTv(
        sessionId: sessionId,
        tvHandshake: tvHandshake,
        phonePublicKeyBytes: phone.publicKeyBytes,
      );
      addTearDown(() {
        tvHandshake.destroy();
        phone.destroy();
        tv.destroy();
      });

      final first = await phone.encryptToTv(
        type: 'input',
        plaintext: [1, 2, 3],
      );
      final changed = EncryptedPairingMessage(
        sessionId: first.sessionId,
        sequence: first.sequence,
        type: 'otherType',
        nonce: first.nonce,
        ciphertext: first.ciphertext,
        tag: first.tag,
      );
      expect(
        () => tv.decryptFromPhone(changed),
        throwsA(isA<PairingCryptoException>()),
      );
      expect(await tv.decryptFromPhone(first), orderedEquals([1, 2, 3]));
      expect(
        () => tv.decryptFromPhone(first),
        throwsA(isA<PairingCryptoException>()),
      );
    },
  );

  test('rejects malformed public keys and message encodings', () {
    expect(
      () => PairingCryptoSession.decodeBytes('not base64?'),
      throwsA(isA<PairingCryptoException>()),
    );
    expect(
      () => EncryptedPairingMessage.fromJson({
        'v': 1,
        'type': 'input',
        'sessionId': 's',
        'seq': 1,
        'nonce': 'AA',
        'ciphertext': 'AA',
        'tag': 'AA',
        'extra': true,
      }),
      throwsA(isA<PairingCryptoException>()),
    );
  });

  test('rejects the low-order all-zero X25519 public key', () async {
    expect(
      PairingCryptoSession.createForPhone(
        sessionId: 'invalid-peer-key',
        tvPublicKeyBytes: List<int>.filled(32, 0),
      ),
      throwsA(isA<PairingCryptoException>()),
    );
  });

  test(
    'matches the phone companion Web Crypto interoperability vector',
    () async {
      final vector =
          jsonDecode(
                await File(
                  'phone_companion/crypto_test_vectors.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      List<int> fromHex(String value) => [
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ];
      final x25519 = X25519();
      final tvKeyPair = await x25519.newKeyPairFromSeed(
        fromHex(
          '77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a',
        ),
      );
      final phoneKeyPair = await x25519.newKeyPairFromSeed(
        fromHex(
          '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb',
        ),
      );
      final handshake = await PairingCryptoSession.createForTv(
        sessionId: vector['sessionId']! as String,
        keyPair: tvKeyPair,
      );
      final phone = await PairingCryptoSession.createForPhone(
        sessionId: vector['sessionId']! as String,
        tvPublicKeyBytes: PairingCryptoSession.decodeBytes(
          vector['tvPublic']! as String,
        ),
        keyPair: phoneKeyPair,
      );
      final tv = await PairingCryptoSession.deriveForTv(
        sessionId: vector['sessionId']! as String,
        tvHandshake: handshake,
        phonePublicKeyBytes: phone.publicKeyBytes,
      );
      addTearDown(() {
        handshake.destroy();
        phone.destroy();
        tv.destroy();
      });

      expect(
        PairingCryptoSession.encodeBytes(handshake.publicKeyBytes),
        vector['tvPublic'],
      );
      expect(
        PairingCryptoSession.encodeBytes(phone.publicKeyBytes),
        vector['phonePublic'],
      );
      expect(await phone.approvalCode(), vector['approvalCode']);
      expect(
        PairingCryptoSession.encodeBytes(phone.sessionToken),
        vector['sessionToken'],
      );

      final message = EncryptedPairingMessage.fromJson({
        'v': 1,
        'type': vector['type'],
        'sessionId': vector['sessionId'],
        'seq': vector['sequence'],
        'nonce': vector['nonce'],
        'ciphertext': vector['ciphertext'],
        'tag': vector['tag'],
      });
      expect(
        utf8.decode(await tv.decryptFromPhone(message)),
        vector['plaintext'],
      );
    },
  );
}
