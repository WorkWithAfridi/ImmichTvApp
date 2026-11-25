import 'pairing_service.dart';
import 'pairing_service_stub.dart'
    if (dart.library.io) 'pairing_service_io.dart'
    as platform;

PhonePairingService createPhonePairingService() =>
    platform.createPhonePairingService();
