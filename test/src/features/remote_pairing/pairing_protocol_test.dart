import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/pairing_protocol.dart';

void main() {
  group('PairingProtocol', () {
    test('starts with an ephemeral invitation and redacts its token', () {
      final protocol = PairingProtocol(entropy: _TestEntropy());

      final invitation = protocol.start();

      expect(invitation.sessionId, isNotEmpty);
      expect(invitation.bootstrapToken.length, 43);
      expect(protocol.snapshot?.phase, PairingPhase.waitingForPhone);
      expect(invitation.toString(), isNot(contains(invitation.bootstrapToken)));
      expect(
        protocol.snapshot.toString(),
        isNot(contains(invitation.bootstrapToken)),
      );
    });

    test('requires TV approval and rotates the bootstrap token', () {
      final protocol = PairingProtocol(entropy: _TestEntropy());
      final invitation = protocol.start();

      final pending = protocol.requestApproval(
        sessionId: invitation.sessionId,
        bootstrapToken: invitation.bootstrapToken,
      );

      expect(pending.phase, PairingPhase.approvalPending);
      expect(pending.verificationCode, '004321');
      expect(
        () => protocol.acceptInput(
          sessionId: invitation.sessionId,
          sessionToken: invitation.bootstrapToken,
          input: _input(1),
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.invalidState,
          ),
        ),
      );

      final grant = protocol.approve(sessionId: invitation.sessionId);
      expect(protocol.snapshot?.phase, PairingPhase.active);
      expect(grant.sessionToken, isNot(invitation.bootstrapToken));
      expect(grant.toString(), isNot(contains(grant.sessionToken)));
      expect(
        () => protocol.requestApproval(
          sessionId: invitation.sessionId,
          bootstrapToken: invitation.bootstrapToken,
        ),
        throwsA(isA<PairingProtocolException>()),
      );
    });

    test('accepts ordered input once and rejects replay and sequence gaps', () {
      final protocol = PairingProtocol(entropy: _TestEntropy());
      final invitation = protocol.start();
      protocol.requestApproval(
        sessionId: invitation.sessionId,
        bootstrapToken: invitation.bootstrapToken,
      );
      final grant = protocol.approve(sessionId: invitation.sessionId);
      final input = _input(1);

      expect(
        protocol.acceptInput(
          sessionId: invitation.sessionId,
          sessionToken: grant.sessionToken,
          input: input,
        ),
        input,
      );
      expect(
        () => protocol.acceptInput(
          sessionId: invitation.sessionId,
          sessionToken: grant.sessionToken,
          input: input,
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.replayedMessage,
          ),
        ),
      );
      expect(
        () => protocol.acceptInput(
          sessionId: invitation.sessionId,
          sessionToken: grant.sessionToken,
          input: _input(3),
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.invalidSequence,
          ),
        ),
      );
    });

    test('revokes session after too many invalid bootstrap credentials', () {
      final protocol = PairingProtocol(
        entropy: _TestEntropy(),
        maxFailedCredentials: 2,
      );
      final invitation = protocol.start();

      expect(
        () => protocol.requestApproval(
          sessionId: invitation.sessionId,
          bootstrapToken: 'wrong-token',
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.invalidCredential,
          ),
        ),
      );
      expect(
        () => protocol.requestApproval(
          sessionId: invitation.sessionId,
          bootstrapToken: 'wrong-token',
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.rateLimited,
          ),
        ),
      );
      expect(protocol.snapshot?.phase, PairingPhase.revoked);
      expect(
        () => protocol.requestApproval(
          sessionId: invitation.sessionId,
          bootstrapToken: invitation.bootstrapToken,
        ),
        throwsA(isA<PairingProtocolException>()),
      );
    });

    test('expires a waiting invitation and clears its credentials', () {
      var now = DateTime.utc(2026, 1, 1);
      final protocol = PairingProtocol(
        entropy: _TestEntropy(),
        clock: () => now,
        pairingLifetime: const Duration(seconds: 30),
      );
      final invitation = protocol.start();
      now = now.add(const Duration(seconds: 30));

      expect(protocol.snapshot?.phase, PairingPhase.expired);
      expect(
        () => protocol.requestApproval(
          sessionId: invitation.sessionId,
          bootstrapToken: invitation.bootstrapToken,
        ),
        throwsA(
          isA<PairingProtocolException>().having(
            (error) => error.failure,
            'failure',
            PairingFailure.expired,
          ),
        ),
      );
    });

    test('deny and stop revoke sessions', () {
      final protocol = PairingProtocol(entropy: _TestEntropy());
      final denied = protocol.start();
      protocol.requestApproval(
        sessionId: denied.sessionId,
        bootstrapToken: denied.bootstrapToken,
      );
      protocol.deny(sessionId: denied.sessionId);
      expect(protocol.snapshot?.phase, PairingPhase.revoked);

      final stopped = protocol.start();
      protocol.stop();
      expect(protocol.snapshot?.phase, PairingPhase.revoked);
      expect(
        () => protocol.requestApproval(
          sessionId: stopped.sessionId,
          bootstrapToken: stopped.bootstrapToken,
        ),
        throwsA(isA<PairingProtocolException>()),
      );
    });
  });

  group('PhoneInputEnvelope', () {
    test('round trips a versioned allowlisted message', () {
      final original = _input(1);

      final decoded = PhoneInputEnvelope.fromJson(original.toJson());

      expect(decoded.sequence, 1);
      expect(decoded.field, PairingInputField.apiKey);
      expect(decoded.value, 'personal-key');
    });

    test(
      'rejects unsupported version, field, empty value, and oversized value',
      () {
        final invalidMessages = <Map<String, Object?>>[
          {
            'v': 2,
            'type': 'input',
            'seq': 1,
            'field': 'email',
            'value': 'person@example.com',
          },
          {
            'v': 1,
            'type': 'input',
            'seq': 1,
            'field': 'immichRequest',
            'value': 'anything',
          },
          {'v': 1, 'type': 'input', 'seq': 1, 'field': 'password', 'value': ''},
          {
            'v': 1,
            'type': 'input',
            'seq': 1,
            'field': 'apiKey',
            'value': List<String>.filled(4097, 'x').join(),
          },
        ];

        for (final message in invalidMessages) {
          expect(
            () => PhoneInputEnvelope.fromJson(message),
            throwsA(
              isA<PairingProtocolException>().having(
                (error) => error.failure,
                'failure',
                PairingFailure.invalidMessage,
              ),
            ),
          );
        }
      },
    );

    test('redacts values from diagnostic text', () {
      const secret = 'private-passphrase';
      const input = PhoneInputEnvelope(
        sequence: 1,
        field: PairingInputField.password,
        value: secret,
      );

      expect(input.toString(), isNot(contains(secret)));
    });
  });
}

PhoneInputEnvelope _input(int sequence) => PhoneInputEnvelope(
  sequence: sequence,
  field: PairingInputField.apiKey,
  value: 'personal-key',
);

class _TestEntropy implements PairingEntropy {
  int _byte = 0;

  @override
  List<int> bytes(int count) =>
      List<int>.generate(count, (_) => _byte++ % 256, growable: false);

  @override
  int nextInt(int max) => 4321;
}
