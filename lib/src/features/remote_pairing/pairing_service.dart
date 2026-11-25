import 'dart:async';

import 'pairing_protocol.dart';

enum PairingServiceFailure {
  unsupportedPlatform,
  noLocalNetwork,
  listenerFailed,
}

class PairingServiceException implements Exception {
  const PairingServiceException(this.failure);

  final PairingServiceFailure failure;

  @override
  String toString() => 'PairingServiceException($failure)';
}

class PairingConnection {
  const PairingConnection({
    required this.invitation,
    required this.qrUri,
    required this.manualUris,
  });

  final PairingInvitation invitation;
  final Uri qrUri;
  final List<Uri> manualUris;

  @override
  String toString() =>
      'PairingConnection(sessionId: ${invitation.sessionId}, uri: [REDACTED])';
}

abstract interface class PhonePairingService {
  bool get isSupported;

  PairingSnapshot? get snapshot;

  Stream<PairingSnapshot?> get updates;

  Future<PairingConnection> start();

  PairingSnapshot approve();

  PairingSnapshot deny();

  Future<void> stop();

  Future<void> dispose();
}
