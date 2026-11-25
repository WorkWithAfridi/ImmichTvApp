import 'package:flutter_test/flutter_test.dart';
import 'package:immichtv/src/features/remote_pairing/remote_command.dart';

void main() {
  group('RemoteCommand', () {
    test(
      'round trips each supported command without adding arbitrary fields',
      () {
        final commands = [
          {'v': 1, 'type': 'remoteCommand', 'seq': 1, 'command': 'select'},
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 2,
            'command': 'navigate',
            'direction': 'left',
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 3,
            'command': 'textInput',
            'text': 'Family trip',
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 4,
            'command': 'seekBy',
            'seconds': -30,
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 5,
            'command': 'togglePlayback',
          },
          {'v': 1, 'type': 'remoteCommand', 'seq': 6, 'command': 'back'},
          {'v': 1, 'type': 'remoteCommand', 'seq': 7, 'command': 'disconnect'},
        ];

        for (final payload in commands) {
          final decoded = RemoteCommand.fromJson(payload);
          expect(RemoteCommand.fromJson(decoded.toJson()).toJson(), payload);
        }
      },
    );

    test(
      'rejects unknown commands, malformed values, and extra properties',
      () {
        final malformed = [
          {'v': 1, 'type': 'remoteCommand', 'seq': 1, 'command': 'rawKey'},
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 1,
            'command': 'navigate',
            'direction': 'diagonal',
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 1,
            'command': 'textInput',
            'text': List.filled(RemoteCommand.maxTextLength + 1, 'x').join(),
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 1,
            'command': 'seekBy',
            'seconds': 61,
          },
          {
            'v': 1,
            'type': 'remoteCommand',
            'seq': 1,
            'command': 'back',
            'url': 'https://example.com',
          },
        ];

        for (final payload in malformed) {
          expect(
            () => RemoteCommand.fromJson(payload),
            throwsA(
              isA<RemoteCommandException>().having(
                (error) => error.failure,
                'failure',
                RemoteCommandFailure.invalidMessage,
              ),
            ),
          );
        }
      },
    );

    test('redacts text from diagnostics', () {
      final command = RemoteCommand.fromJson({
        'v': 1,
        'type': 'remoteCommand',
        'seq': 1,
        'command': 'textInput',
        'text': 'private search',
      });

      expect(command.toString(), isNot(contains('private search')));
      expect(command.toString(), contains('[REDACTED]'));
    });
  });

  group('RemoteCommandSequence', () {
    test('accepts ordered commands once and disconnects terminally', () {
      final sequence = RemoteCommandSequence();
      final first = RemoteCommand.fromJson({
        'v': 1,
        'type': 'remoteCommand',
        'seq': 1,
        'command': 'select',
      });
      final disconnect = RemoteCommand.fromJson({
        'v': 1,
        'type': 'remoteCommand',
        'seq': 2,
        'command': 'disconnect',
      });

      expect(sequence.accept(first), same(first));
      expect(
        () => sequence.accept(first),
        throwsA(
          isA<RemoteCommandException>().having(
            (error) => error.failure,
            'failure',
            RemoteCommandFailure.replayedMessage,
          ),
        ),
      );
      expect(sequence.accept(disconnect), same(disconnect));
      expect(sequence.isConnected, isFalse);
      expect(
        () => sequence.accept(first),
        throwsA(
          isA<RemoteCommandException>().having(
            (error) => error.failure,
            'failure',
            RemoteCommandFailure.disconnected,
          ),
        ),
      );
    });

    test('rejects gaps and allows retry after a gap', () {
      final sequence = RemoteCommandSequence();
      final skipped = RemoteCommand.fromJson({
        'v': 1,
        'type': 'remoteCommand',
        'seq': 2,
        'command': 'back',
      });
      final first = RemoteCommand.fromJson({
        'v': 1,
        'type': 'remoteCommand',
        'seq': 1,
        'command': 'back',
      });

      expect(
        () => sequence.accept(skipped),
        throwsA(
          isA<RemoteCommandException>().having(
            (error) => error.failure,
            'failure',
            RemoteCommandFailure.invalidSequence,
          ),
        ),
      );
      expect(sequence.accept(first), same(first));
    });
  });
}
