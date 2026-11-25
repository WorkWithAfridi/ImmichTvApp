import 'dart:convert';
import 'dart:math';

enum PairingPhase {
  stopped,
  waitingForPhone,
  approvalPending,
  active,
  expired,
  revoked,
}

enum PairingInputField { serverUrl, email, password, apiKey }

enum PairingFailure {
  noSession,
  invalidSession,
  invalidCredential,
  rateLimited,
  invalidState,
  expired,
  invalidMessage,
  invalidSequence,
  replayedMessage,
}

class PairingProtocolException implements Exception {
  const PairingProtocolException(this.failure);

  final PairingFailure failure;

  @override
  String toString() => 'PairingProtocolException($failure)';
}

abstract interface class PairingEntropy {
  List<int> bytes(int count);

  int nextInt(int max);
}

class SecurePairingEntropy implements PairingEntropy {
  SecurePairingEntropy() : _random = Random.secure();

  final Random _random;

  @override
  List<int> bytes(int count) =>
      List<int>.generate(count, (_) => _random.nextInt(256), growable: false);

  @override
  int nextInt(int max) => _random.nextInt(max);
}

class PairingInvitation {
  const PairingInvitation({
    required this.sessionId,
    required this.bootstrapToken,
    required this.expiresAt,
  });

  final String sessionId;
  final String bootstrapToken;
  final DateTime expiresAt;

  @override
  String toString() =>
      'PairingInvitation(sessionId: $sessionId, token: [REDACTED])';
}

class PairingGrant {
  const PairingGrant({
    required this.sessionId,
    required this.sessionToken,
    required this.expiresAt,
  });

  final String sessionId;
  final String sessionToken;
  final DateTime expiresAt;

  @override
  String toString() => 'PairingGrant(sessionId: $sessionId, token: [REDACTED])';
}

class PairingSnapshot {
  const PairingSnapshot({
    required this.sessionId,
    required this.phase,
    required this.expiresAt,
    this.verificationCode,
  });

  final String sessionId;
  final PairingPhase phase;
  final DateTime expiresAt;
  final String? verificationCode;
}

/// Versioned, allowlisted phone input message. Its value is intentionally
/// excluded from `toString` because it may contain credentials.
class PhoneInputEnvelope {
  const PhoneInputEnvelope({
    required this.sequence,
    required this.field,
    required this.value,
  });

  static const protocolVersion = 1;
  static const maxValueLength = 4096;

  final int sequence;
  final PairingInputField field;
  final String value;

  factory PhoneInputEnvelope.fromJson(Map<String, Object?> json) {
    if (json['v'] != protocolVersion || json['type'] != 'input') {
      throw const PairingProtocolException(PairingFailure.invalidMessage);
    }

    final sequence = json['seq'];
    final fieldName = json['field'];
    final value = json['value'];
    if (sequence is! int ||
        sequence < 1 ||
        fieldName is! String ||
        value is! String ||
        value.isEmpty ||
        value.length > maxValueLength) {
      throw const PairingProtocolException(PairingFailure.invalidMessage);
    }

    final field = switch (fieldName) {
      'serverUrl' => PairingInputField.serverUrl,
      'email' => PairingInputField.email,
      'password' => PairingInputField.password,
      'apiKey' => PairingInputField.apiKey,
      _ => throw const PairingProtocolException(PairingFailure.invalidMessage),
    };

    return PhoneInputEnvelope(sequence: sequence, field: field, value: value);
  }

  Map<String, Object> toJson() => {
    'v': protocolVersion,
    'type': 'input',
    'seq': sequence,
    'field': switch (field) {
      PairingInputField.serverUrl => 'serverUrl',
      PairingInputField.email => 'email',
      PairingInputField.password => 'password',
      PairingInputField.apiKey => 'apiKey',
    },
    'value': value,
  };

  String encode() => jsonEncode(toJson());

  @override
  String toString() =>
      'PhoneInputEnvelope(sequence: $sequence, field: $field, value: [REDACTED])';
}

/// In-memory pairing state machine. A transport must enforce the approved
/// network security design before forwarding any credential-bearing input.
class PairingProtocol {
  PairingProtocol({
    PairingEntropy? entropy,
    DateTime Function()? clock,
    this.pairingLifetime = const Duration(minutes: 3),
    this.activeLifetime = const Duration(minutes: 30),
    this.maxFailedCredentials = 5,
  }) : _entropy = entropy ?? SecurePairingEntropy(),
       _clock = clock ?? DateTime.now {
    if (pairingLifetime <= Duration.zero ||
        activeLifetime <= Duration.zero ||
        maxFailedCredentials < 1) {
      throw ArgumentError(
        'Pairing durations and attempt limit must be positive.',
      );
    }
  }

  final PairingEntropy _entropy;
  final DateTime Function() _clock;
  final Duration pairingLifetime;
  final Duration activeLifetime;
  final int maxFailedCredentials;
  _PairingSession? _session;

  PairingSnapshot? get snapshot {
    _expireIfNeeded();
    final session = _session;
    if (session == null) return null;
    return PairingSnapshot(
      sessionId: session.id,
      phase: session.phase,
      expiresAt: session.expiresAt,
      verificationCode: session.verificationCode,
    );
  }

  PairingInvitation start() {
    _session = null;
    final now = _clock();
    final id = _randomToken(16);
    final token = _randomToken(32);
    final expiresAt = now.add(pairingLifetime);
    _session = _PairingSession(
      id: id,
      phase: PairingPhase.waitingForPhone,
      bootstrapToken: token,
      expiresAt: expiresAt,
    );
    return PairingInvitation(
      sessionId: id,
      bootstrapToken: token,
      expiresAt: expiresAt,
    );
  }

  PairingSnapshot requestApproval({
    required String sessionId,
    required String bootstrapToken,
  }) {
    final session = _requireSession(sessionId);
    _requirePhase(session, PairingPhase.waitingForPhone);
    if (!_matches(session.bootstrapToken, bootstrapToken)) {
      _recordFailedCredential(session);
      throw const PairingProtocolException(PairingFailure.invalidCredential);
    }

    session.phase = PairingPhase.approvalPending;
    session.verificationCode = _entropy
        .nextInt(1000000)
        .toString()
        .padLeft(6, '0');
    return snapshot!;
  }

  PairingGrant approve({required String sessionId}) {
    final session = _requireSession(sessionId);
    _requirePhase(session, PairingPhase.approvalPending);

    final token = _randomToken(32);
    session
      ..phase = PairingPhase.active
      ..bootstrapToken = null
      ..sessionToken = token
      ..verificationCode = null
      ..expiresAt = _clock().add(activeLifetime)
      ..lastAcceptedSequence = 0;
    return PairingGrant(
      sessionId: session.id,
      sessionToken: token,
      expiresAt: session.expiresAt,
    );
  }

  void deny({required String sessionId}) {
    final session = _requireSession(sessionId);
    _requirePhase(session, PairingPhase.approvalPending);
    _terminate(session, PairingPhase.revoked);
  }

  PhoneInputEnvelope acceptInput({
    required String sessionId,
    required String sessionToken,
    required PhoneInputEnvelope input,
  }) {
    final session = _requireSession(sessionId);
    _requirePhase(session, PairingPhase.active);
    if (!_matches(session.sessionToken, sessionToken)) {
      _recordFailedCredential(session);
      throw const PairingProtocolException(PairingFailure.invalidCredential);
    }
    final lastSequence = session.lastAcceptedSequence;
    if (input.sequence <= lastSequence) {
      throw const PairingProtocolException(PairingFailure.replayedMessage);
    }
    if (input.sequence != lastSequence + 1) {
      throw const PairingProtocolException(PairingFailure.invalidSequence);
    }
    session.lastAcceptedSequence = input.sequence;
    return input;
  }

  void revoke({required String sessionId}) {
    final session = _requireSession(sessionId);
    if (session.phase == PairingPhase.expired ||
        session.phase == PairingPhase.revoked) {
      return;
    }
    _terminate(session, PairingPhase.revoked);
  }

  void stop() {
    final session = _session;
    if (session != null &&
        session.phase != PairingPhase.expired &&
        session.phase != PairingPhase.revoked) {
      _terminate(session, PairingPhase.revoked);
    }
  }

  _PairingSession _requireSession(String sessionId) {
    _expireIfNeeded();
    final session = _session;
    if (session == null) {
      throw const PairingProtocolException(PairingFailure.noSession);
    }
    if (session.id != sessionId) {
      throw const PairingProtocolException(PairingFailure.invalidSession);
    }
    if (session.phase == PairingPhase.expired) {
      throw const PairingProtocolException(PairingFailure.expired);
    }
    return session;
  }

  void _requirePhase(_PairingSession session, PairingPhase expected) {
    if (session.phase != expected) {
      throw const PairingProtocolException(PairingFailure.invalidState);
    }
  }

  void _expireIfNeeded() {
    final session = _session;
    if (session != null &&
        session.phase != PairingPhase.expired &&
        session.phase != PairingPhase.revoked &&
        !_clock().isBefore(session.expiresAt)) {
      _terminate(session, PairingPhase.expired);
    }
  }

  void _recordFailedCredential(_PairingSession session) {
    session.failedCredentials++;
    if (session.failedCredentials >= maxFailedCredentials) {
      _terminate(session, PairingPhase.revoked);
      throw const PairingProtocolException(PairingFailure.rateLimited);
    }
  }

  void _terminate(_PairingSession session, PairingPhase phase) {
    session
      ..phase = phase
      ..bootstrapToken = null
      ..sessionToken = null
      ..verificationCode = null;
  }

  String _randomToken(int byteCount) =>
      base64Url.encode(_entropy.bytes(byteCount)).replaceAll('=', '');

  bool _matches(String? expected, String actual) {
    if (expected == null || expected.length != actual.length) return false;
    var difference = 0;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^ actual.codeUnitAt(i);
    }
    return difference == 0;
  }
}

class _PairingSession {
  _PairingSession({
    required this.id,
    required this.phase,
    required this.bootstrapToken,
    required this.expiresAt,
  });

  final String id;
  PairingPhase phase;
  String? bootstrapToken;
  String? sessionToken;
  DateTime expiresAt;
  String? verificationCode;
  int failedCredentials = 0;
  int lastAcceptedSequence = 0;
}
