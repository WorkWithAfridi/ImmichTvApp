import 'dart:async';
import 'dart:convert';

enum RemoteDirection { up, down, left, right }

enum RemoteCommandType {
  navigate,
  select,
  back,
  textInput,
  backspace,
  clearText,
  submitText,
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

enum RemoteCommandOutcome { ok, ignored, unavailable, invalid }

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
        return _simple(sequence, RemoteCommandType.select, json);
      case 'back':
        return _simple(sequence, RemoteCommandType.back, json);
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
      case 'backspace':
        return _simple(sequence, RemoteCommandType.backspace, json);
      case 'clearText':
        return _simple(sequence, RemoteCommandType.clearText, json);
      case 'submitText':
        return _simple(sequence, RemoteCommandType.submitText, json);
      case 'togglePlayback':
        return _simple(sequence, RemoteCommandType.togglePlayback, json);
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
        return _simple(sequence, RemoteCommandType.disconnect, json);
      default:
        throw const RemoteCommandException(RemoteCommandFailure.invalidMessage);
    }
  }

  static RemoteCommand _simple(
    int sequence,
    RemoteCommandType type,
    Map<String, Object?> json,
  ) {
    _requireKeys(json, {'v', 'type', 'seq', 'command'});
    return RemoteCommand._(sequence: sequence, type: type);
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
        RemoteCommandType.backspace => 'backspace',
        RemoteCommandType.clearText => 'clearText',
        RemoteCommandType.submitText => 'submitText',
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

/// One authenticated command handed from the transport to the TV controller.
///
/// The transport must call [complete] so the phone receives an ack.
class RemoteCommandRequest {
  RemoteCommandRequest({
    required this.id,
    required this.sessionId,
    required this.command,
  });

  final String id;
  final String sessionId;
  final RemoteCommand command;

  final Completer<RemoteCommandOutcome> _outcome =
      Completer<RemoteCommandOutcome>();
  bool _isCompleted = false;

  Future<RemoteCommandOutcome> get outcome => _outcome.future;

  void complete(RemoteCommandOutcome outcome) {
    if (_isCompleted) return;
    _isCompleted = true;
    if (!_outcome.isCompleted) _outcome.complete(outcome);
  }

  @override
  String toString() =>
      'RemoteCommandRequest(id: $id, command: $command)';
}

/// Acknowledgement sent back to the phone for one command.
class RemoteCommandAck {
  const RemoteCommandAck({
    required this.sequence,
    required this.accepted,
    required this.outcome,
  });

  static const protocolVersion = 1;

  final int sequence;
  final bool accepted;
  final RemoteCommandOutcome outcome;

  Map<String, Object> toJson() => {
    'v': protocolVersion,
    'type': 'ack',
    'seq': sequence,
    'accepted': accepted,
    'outcome': outcome.name,
  };

  @override
  String toString() =>
      'RemoteCommandAck(sequence: $sequence, outcome: $outcome)';
}

/// Enforces ordered, single-use commands for one active phone session.
/// Authentication and transport confidentiality remain the transport's job.
class RemoteCommandSequence {
  RemoteCommandSequence({int initial = 0}) : _lastAccepted = initial;

  int _lastAccepted;
  bool _isConnected = true;

  int get lastAccepted => _lastAccepted;
  bool get isConnected => _isConnected;

  void reset(int lastAccepted) {
    _lastAccepted = lastAccepted;
    _isConnected = true;
  }

  /// Advances the watermark without clearing a terminal disconnect state.
  void advanceTo(int sequence) {
    if (_isConnected && sequence > _lastAccepted) _lastAccepted = sequence;
  }

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
