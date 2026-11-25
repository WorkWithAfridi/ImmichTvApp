import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// The shared P-256/HKDF/AES-GCM session keys for one QR pairing attempt.
///
/// The companion page uses the same wire formats and derives the same keys
/// with Web Crypto. Keep changes synchronized with `phone_companion/crypto.js`.
class PairingCryptoSession {
  PairingCryptoSession._({
    required this.sessionId,
    required this.localKeyPair,
    required this.remotePublicKey,
    required this.publicKeyBytes,
    required this.remotePublicKeyBytes,
    required this.phonePublicKeyBytes,
    required List<int> keyMaterial,
  }) : _clientToTvKey = SecretKey(keyMaterial.sublist(0, 32)),
       _tvToClientKey = SecretKey(keyMaterial.sublist(32, 64)),
       _verificationKey = SecretKey(keyMaterial.sublist(64, 96)),
       _sessionTokenBytes = keyMaterial.sublist(96, 128);

  static const protocolVersion = 1;
  static const _hkdfSaltPrefix = 'immich-tv-pairing-v1:';
  static const _hkdfInfo = 'immich-tv-session-keyset-v1';
  static const _approvalLabel = 'immich-tv-approval-code-v1';

  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 128);
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Hmac _hmac = Hmac.sha256();

  final String sessionId;
  final KeyPair localKeyPair;
  final SimplePublicKey remotePublicKey;
  final List<int> publicKeyBytes;
  final List<int> remotePublicKeyBytes;
  final List<int> phonePublicKeyBytes;
  final SecretKey _clientToTvKey;
  final SecretKey _tvToClientKey;
  final SecretKey _verificationKey;
  final List<int> _sessionTokenBytes;
  var _isDestroyed = false;
  var _phoneToTvSequence = 0;
  var _tvToPhoneSequence = 0;

  /// Starts the TV side of a pairing handshake and creates the QR public key.
  static Future<PairingCryptoHandshake> createForTv({
    required String sessionId,
  }) async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return PairingCryptoHandshake(
      sessionId: sessionId,
      keyPair: keyPair,
      publicKeyBytes: publicKey.bytes,
    );
  }

  /// Completes key derivation once the phone's ephemeral public key arrives.
  static Future<PairingCryptoSession> deriveForTv({
    required String sessionId,
    required PairingCryptoHandshake tvHandshake,
    required List<int> phonePublicKeyBytes,
  }) async {
    final phonePublicKey = _decodePublicKey(phonePublicKeyBytes);
    return _derive(
      sessionId: sessionId,
      localKeyPair: tvHandshake.keyPair,
      localPublicKeyBytes: tvHandshake.publicKeyBytes,
      remotePublicKey: phonePublicKey,
      remotePublicKeyBytes: phonePublicKeyBytes,
      phonePublicKeyBytes: phonePublicKeyBytes,
    );
  }

  /// Creates the phone side of the handshake from an ephemeral key pair.
  static Future<PairingCryptoSession> createForPhone({
    required String sessionId,
    required List<int> tvPublicKeyBytes,
  }) async {
    final phoneKeyPair = await _x25519.newKeyPair();
    final phonePublicKey = await phoneKeyPair.extractPublicKey();
    final tvPublicKey = _decodePublicKey(tvPublicKeyBytes);
    return _derive(
      sessionId: sessionId,
      localKeyPair: phoneKeyPair,
      localPublicKeyBytes: phonePublicKey.bytes,
      remotePublicKey: tvPublicKey,
      remotePublicKeyBytes: tvPublicKeyBytes,
      phonePublicKeyBytes: _encodePublicKey(phonePublicKey),
    );
  }

  List<int> get sessionToken {
    _ensureAlive();
    return List<int>.unmodifiable(_sessionTokenBytes);
  }

  Future<String> approvalCode() async {
    _ensureAlive();
    final mac = await _hmac.calculateMac(
      utf8.encode(
        '$_approvalLabel|$sessionId|${encodeBytes(phonePublicKeyBytes)}',
      ),
      secretKey: _verificationKey,
    );
    final value =
        ((mac.bytes[0] << 24) |
            (mac.bytes[1] << 16) |
            (mac.bytes[2] << 8) |
            mac.bytes[3]) %
        1000000;
    return value.toString().padLeft(6, '0');
  }

  int get nextPhoneToTvSequence => _phoneToTvSequence + 1;

  int get nextTvToPhoneSequence => _tvToPhoneSequence + 1;

  Future<EncryptedPairingMessage> encryptToTv({
    required String type,
    required List<int> plaintext,
  }) async {
    _ensureAlive();
    final sequence = ++_phoneToTvSequence;
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: _clientToTvKey,
      nonce: nonce,
      aad: _associatedData(
        sessionId: sessionId,
        direction: 'phone-to-tv',
        sequence: sequence,
        type: type,
      ),
    );
    return EncryptedPairingMessage(
      sessionId: sessionId,
      sequence: sequence,
      type: type,
      nonce: box.nonce,
      ciphertext: box.cipherText,
      tag: box.mac.bytes,
    );
  }

  Future<List<int>> decryptFromPhone(EncryptedPairingMessage message) async {
    _ensureAlive();
    if (message.sessionId != sessionId ||
        message.sequence != _phoneToTvSequence + 1) {
      throw const PairingCryptoException('invalid_sequence');
    }
    if (message.nonce.length != 12 || message.tag.length != 16) {
      throw const PairingCryptoException('invalid_ciphertext');
    }
    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(
          message.ciphertext,
          nonce: message.nonce,
          mac: Mac(message.tag),
        ),
        secretKey: _clientToTvKey,
        aad: _associatedData(
          sessionId: sessionId,
          direction: 'phone-to-tv',
          sequence: message.sequence,
          type: message.type,
        ),
      );
      _phoneToTvSequence = message.sequence;
      return plaintext;
    } on SecretBoxAuthenticationError {
      throw const PairingCryptoException('invalid_ciphertext');
    }
  }

  Future<EncryptedPairingMessage> encryptToPhone({
    required String type,
    required List<int> plaintext,
  }) async {
    _ensureAlive();
    final sequence = ++_tvToPhoneSequence;
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: _tvToClientKey,
      nonce: nonce,
      aad: _associatedData(
        sessionId: sessionId,
        direction: 'tv-to-phone',
        sequence: sequence,
        type: type,
      ),
    );
    return EncryptedPairingMessage(
      sessionId: sessionId,
      sequence: sequence,
      type: type,
      nonce: box.nonce,
      ciphertext: box.cipherText,
      tag: box.mac.bytes,
    );
  }

  Future<List<int>> decryptFromTv(EncryptedPairingMessage message) async {
    _ensureAlive();
    if (message.sessionId != sessionId ||
        message.sequence != _tvToPhoneSequence + 1) {
      throw const PairingCryptoException('invalid_sequence');
    }
    if (message.nonce.length != 12 || message.tag.length != 16) {
      throw const PairingCryptoException('invalid_ciphertext');
    }
    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(
          message.ciphertext,
          nonce: message.nonce,
          mac: Mac(message.tag),
        ),
        secretKey: _tvToClientKey,
        aad: _associatedData(
          sessionId: sessionId,
          direction: 'tv-to-phone',
          sequence: message.sequence,
          type: message.type,
        ),
      );
      _tvToPhoneSequence = message.sequence;
      return plaintext;
    } on SecretBoxAuthenticationError {
      throw const PairingCryptoException('invalid_ciphertext');
    }
  }

  void destroy() {
    if (_isDestroyed) return;
    _isDestroyed = true;
    localKeyPair.destroy();
    _clientToTvKey.destroy();
    _tvToClientKey.destroy();
    _verificationKey.destroy();
    _sessionTokenBytes.fillRange(0, _sessionTokenBytes.length, 0);
    _phoneToTvSequence = 0;
    _tvToPhoneSequence = 0;
  }

  void _ensureAlive() {
    if (_isDestroyed) throw const PairingCryptoException('session_destroyed');
  }

  static Future<PairingCryptoSession> _derive({
    required String sessionId,
    required KeyPair localKeyPair,
    required List<int> localPublicKeyBytes,
    required SimplePublicKey remotePublicKey,
    required List<int> remotePublicKeyBytes,
    required List<int> phonePublicKeyBytes,
  }) async {
    if (sessionId.isEmpty || sessionId.length > 128) {
      throw const PairingCryptoException('invalid_session');
    }
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    final keyMaterial = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('$_hkdfSaltPrefix$sessionId'),
      info: utf8.encode(_hkdfInfo),
    );
    final bytes = (await keyMaterial.extractBytes()).toList(growable: false);
    sharedSecret.destroy();
    keyMaterial.destroy();
    final session = PairingCryptoSession._(
      sessionId: sessionId,
      localKeyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
      publicKeyBytes: localPublicKeyBytes,
      remotePublicKeyBytes: remotePublicKeyBytes,
      phonePublicKeyBytes: phonePublicKeyBytes,
      keyMaterial: bytes,
    );
    bytes.fillRange(0, bytes.length, 0);
    return session;
  }

  static List<int> _encodePublicKey(SimplePublicKey publicKey) =>
      publicKey.bytes;

  static SimplePublicKey _decodePublicKey(List<int> bytes) {
    if (bytes.length != 32) {
      throw const PairingCryptoException('invalid_public_key');
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  static List<int> _associatedData({
    required String sessionId,
    required String direction,
    required int sequence,
    required String type,
  }) =>
      utf8.encode('immich-tv-pairing|1|$sessionId|$direction|$sequence|$type');

  static String encodeBytes(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> decodeBytes(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const PairingCryptoException('invalid_encoding');
    }
    try {
      return base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      throw const PairingCryptoException('invalid_encoding');
    }
  }
}

class PairingCryptoHandshake {
  PairingCryptoHandshake({
    required this.sessionId,
    required this.keyPair,
    required this.publicKeyBytes,
  });

  final String sessionId;
  final KeyPair keyPair;
  final List<int> publicKeyBytes;

  void destroy() => keyPair.destroy();
}

class EncryptedPairingMessage {
  const EncryptedPairingMessage({
    required this.sessionId,
    required this.sequence,
    required this.type,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  final String sessionId;
  final int sequence;
  final String type;
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> tag;

  Map<String, Object> toJson() => {
    'v': PairingCryptoSession.protocolVersion,
    'type': type,
    'sessionId': sessionId,
    'seq': sequence,
    'nonce': PairingCryptoSession.encodeBytes(nonce),
    'ciphertext': PairingCryptoSession.encodeBytes(ciphertext),
    'tag': PairingCryptoSession.encodeBytes(tag),
  };

  factory EncryptedPairingMessage.fromJson(Map<String, Object?> json) {
    if (json.length != 7 ||
        json['v'] != PairingCryptoSession.protocolVersion ||
        json['type'] is! String ||
        json['sessionId'] is! String ||
        json['seq'] is! int ||
        (json['seq']! as int) < 1 ||
        json['nonce'] is! String ||
        json['ciphertext'] is! String ||
        json['tag'] is! String) {
      throw const PairingCryptoException('invalid_message');
    }
    return EncryptedPairingMessage(
      sessionId: json['sessionId']! as String,
      sequence: json['seq']! as int,
      type: json['type']! as String,
      nonce: PairingCryptoSession.decodeBytes(json['nonce']! as String),
      ciphertext: PairingCryptoSession.decodeBytes(
        json['ciphertext']! as String,
      ),
      tag: PairingCryptoSession.decodeBytes(json['tag']! as String),
    );
  }

  @override
  String toString() =>
      'EncryptedPairingMessage(sessionId: $sessionId, sequence: $sequence, type: $type, payload: [REDACTED])';
}

class PairingCryptoException implements Exception {
  const PairingCryptoException(this.code);

  final String code;

  @override
  String toString() => 'PairingCryptoException($code)';
}
