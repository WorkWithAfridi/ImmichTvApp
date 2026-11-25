import 'pairing_service.dart';
import 'pairing_protocol.dart';

PhonePairingService createPhonePairingService() =>
    _UnsupportedPhonePairingService();

class _UnsupportedPhonePairingService implements PhonePairingService {
  @override
  bool get isSupported => false;

  @override
  PairingSnapshot? get snapshot => null;

  @override
  Stream<PairingSnapshot?> get updates => const Stream.empty();

  @override
  Stream<PhoneOnboardingInput> get onboardingInputs => const Stream.empty();

  @override
  Future<PairingConnection> start() => Future.error(
    const PairingServiceException(PairingServiceFailure.unsupportedPlatform),
  );

  @override
  PairingSnapshot approve() => throw const PairingServiceException(
    PairingServiceFailure.unsupportedPlatform,
  );

  @override
  PairingSnapshot deny() => throw const PairingServiceException(
    PairingServiceFailure.unsupportedPlatform,
  );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
