import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
}
