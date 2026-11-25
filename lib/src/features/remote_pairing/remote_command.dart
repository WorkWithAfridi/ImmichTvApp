import 'dart:convert';

enum RemoteDirection { up, down, left, right }

enum RemoteCommandType {
  navigate,
  select,
  back,
  textInput,
  togglePlayback,
  seekBy,
  disconnect,
}

enum RemoteCommandFailure {
  invalidMessage,
  invalidSequence,
  replayedMessage,
  disconnected,
}

class RemoteCommandException implements Exception {
  const RemoteCommandException(this.failure);

  final RemoteCommandFailure failure;

  @override
  String toString() => 'RemoteCommandException($failure)';
}

/// A deliberately narrow, versioned command sent by a paired phone.
///
/// This contract does not represent raw key events, app routes, or Immich API
/// calls. Its values must be mapped to app-level actions by a TV-side adapter.
class RemoteCommand {
  const RemoteCommand._({
    required this.sequence,
    required this.type,
    this.direction,
    this.text,
    this.seekSeconds,
  });

  static const protocolVersion = 1;
  static const maxTextLength = 256;
  static const maxSeekSeconds = 60;

  final int sequence;
  final RemoteCommandType type;
  final RemoteDirection? direction;
  final String? text;
  final int? seekSeconds;

  factory RemoteCommand.fromJson(Map<String, Object?> json) {
    if (json['v'] != protocolVersion ||
        json['type'] != 'remoteCommand' ||
        json['seq'] is! int ||
        (json['seq']! as int) < 1) {
      throw const RemoteCommandException(RemoteCommandFailure.invalidMessage);
    }
    final sequence = json['seq']! as int;
    final command = json['command'];
    switch (command) {
      case 'navigate':
        final direction = switch (json['direction']) {
          'up' => RemoteDirection.up,
          'down' => RemoteDirection.down,
          'left' => RemoteDirection.left,
          'right' => RemoteDirection.right,
          _ => throw const RemoteCommandException(
            RemoteCommandFailure.invalidMessage,
          ),
        };
        _requireKeys(json, {'v', 'type', 'seq', 'command', 'direction'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.navigate,
          direction: direction,
        );
      case 'select':
        _requireKeys(json, {'v', 'type', 'seq', 'command'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.select,
        );
      case 'back':
        _requireKeys(json, {'v', 'type', 'seq', 'command'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.back,
        );
      case 'textInput':
        final text = json['text'];
        if (text is! String || text.isEmpty || text.length > maxTextLength) {
          throw const RemoteCommandException(
            RemoteCommandFailure.invalidMessage,
          );
        }
        _requireKeys(json, {'v', 'type', 'seq', 'command', 'text'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.textInput,
          text: text,
        );
      case 'togglePlayback':
        _requireKeys(json, {'v', 'type', 'seq', 'command'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.togglePlayback,
        );
      case 'seekBy':
        final seconds = json['seconds'];
        if (seconds is! int || seconds == 0 || seconds.abs() > maxSeekSeconds) {
          throw const RemoteCommandException(
            RemoteCommandFailure.invalidMessage,
          );
        }
        _requireKeys(json, {'v', 'type', 'seq', 'command', 'seconds'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.seekBy,
          seekSeconds: seconds,
        );
      case 'disconnect':
        _requireKeys(json, {'v', 'type', 'seq', 'command'});
        return RemoteCommand._(
          sequence: sequence,
          type: RemoteCommandType.disconnect,
        );
      default:
        throw const RemoteCommandException(RemoteCommandFailure.invalidMessage);
    }
  }

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'v': protocolVersion,
      'type': 'remoteCommand',
      'seq': sequence,
      'command': switch (type) {
        RemoteCommandType.navigate => 'navigate',
        RemoteCommandType.select => 'select',
        RemoteCommandType.back => 'back',
        RemoteCommandType.textInput => 'textInput',
        RemoteCommandType.togglePlayback => 'togglePlayback',
        RemoteCommandType.seekBy => 'seekBy',
        RemoteCommandType.disconnect => 'disconnect',
      },
    };
    if (direction case final value?) json['direction'] = value.name;
    if (text case final value?) json['text'] = value;
    if (seekSeconds case final value?) json['seconds'] = value;
    return json;
  }

  String encode() => jsonEncode(toJson());

  @override
  String toString() => type == RemoteCommandType.textInput
      ? 'RemoteCommand(sequence: $sequence, type: $type, text: [REDACTED])'
      : 'RemoteCommand(sequence: $sequence, type: $type)';

  static void _requireKeys(Map<String, Object?> json, Set<String> expected) {
    if (json.keys.toSet().difference(expected).isNotEmpty ||
        expected.difference(json.keys.toSet()).isNotEmpty) {
      throw const RemoteCommandException(RemoteCommandFailure.invalidMessage);
    }
  }
}

/// Enforces ordered, single-use commands for one active phone session.
/// Authentication and transport confidentiality remain the transport's job.
class RemoteCommandSequence {
  int _lastAccepted = 0;
  bool _isConnected = true;

  int get lastAccepted => _lastAccepted;
  bool get isConnected => _isConnected;

  RemoteCommand accept(RemoteCommand command) {
    if (!_isConnected) {
      throw const RemoteCommandException(RemoteCommandFailure.disconnected);
    }
    if (command.sequence <= _lastAccepted) {
      throw const RemoteCommandException(RemoteCommandFailure.replayedMessage);
    }
    if (command.sequence != _lastAccepted + 1) {
      throw const RemoteCommandException(RemoteCommandFailure.invalidSequence);
    }
    _lastAccepted = command.sequence;
    if (command.type == RemoteCommandType.disconnect) {
      _isConnected = false;
    }
    return command;
  }
}
