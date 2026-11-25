import 'dart:async';

import 'pairing_protocol.dart';
import 'remote_command.dart';

enum PairingServiceFailure {
  unsupportedPlatform,
  noLocalNetwork,
  companionUnavailable,
  listenerFailed,
}

class PairingServiceException implements Exception {
  const PairingServiceException(this.failure);

  final PairingServiceFailure failure;

  @override
  String toString() => 'PairingServiceException($failure)';
}

/// What the phone is being connected for. Both modes use the same TV-hosted
/// session; only the companion surface shown to the phone differs.
enum PhonePairingMode { setup, remote }

class PairingConnection {
  const PairingConnection({
    required this.invitation,
    required this.qrUri,
    required this.manualUris,
    this.mode = PhonePairingMode.setup,
  });

  final PairingInvitation invitation;
  final Uri qrUri;
  final List<Uri> manualUris;
  final PhonePairingMode mode;

  @override
  String toString() =>
      'PairingConnection(sessionId: ${invitation.sessionId}, mode: $mode, uri: [REDACTED])';
}

abstract interface class PhonePairingService {
  bool get isSupported;

  PairingSnapshot? get snapshot;

  Stream<PairingSnapshot?> get updates;

  Stream<PhoneOnboardingInput> get onboardingInputs;

  /// Authenticated remote commands awaiting a TV-side decision.
  Stream<RemoteCommandRequest> get remoteCommands;

  Future<PairingConnection> start({
    PhonePairingMode mode = PhonePairingMode.setup,
  });

  PairingSnapshot approve();

  PairingSnapshot deny();

  /// Resolves a dispatched command so the transport can acknowledge it.
  void resolveRemoteCommand(
    RemoteCommandRequest request,
    RemoteCommandOutcome outcome,
  );

  Future<void> stop();

  Future<void> dispose();
}
