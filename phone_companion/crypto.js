const encoder = new TextEncoder();

export function fromBase64Url(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error('invalid_invitation');
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

export function toBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export async function createPhoneCryptoSession(tvPublicBytes, sessionId) {
  const phoneKeys = await crypto.subtle.generateKey({ name: 'X25519' }, false, ['deriveBits']);
  return derivePhoneCryptoSession(
    tvPublicBytes,
    sessionId,
    phoneKeys,
    new Uint8Array(await crypto.subtle.exportKey('raw', phoneKeys.publicKey)),
  );
}

export async function derivePhoneCryptoSession(tvPublicBytes, sessionId, phoneKeys, phonePublicBytes) {
  let shared;
  try {
    const tvPublicKey = await crypto.subtle.importKey('raw', tvPublicBytes, { name: 'X25519' }, false, []);
    shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'X25519', public: tvPublicKey }, phoneKeys.privateKey, 256));
  } catch (_) {
    throw new Error('invalid_public_key');
  }
  if (shared.every((byte) => byte === 0)) {
    shared.fill(0);
    throw new Error('invalid_public_key');
  }
  const hkdfMaterial = await crypto.subtle.importKey('raw', shared, 'HKDF', false, ['deriveBits']);
  shared.fill(0);
  const salt = encoder.encode(`immich-tv-pairing-v1:${sessionId}`);
  const keyset = new Uint8Array(await crypto.subtle.deriveBits({
    name: 'HKDF', hash: 'SHA-256', salt,
    info: encoder.encode('immich-tv-session-keyset-v1'),
  }, hkdfMaterial, 1024));
  const inputKey = await crypto.subtle.importKey('raw', keyset.slice(0, 32), { name: 'AES-GCM' }, false, ['encrypt']);
  const outputKey = await crypto.subtle.importKey('raw', keyset.slice(32, 64), { name: 'AES-GCM' }, false, ['decrypt']);
  const proofKey = await crypto.subtle.importKey('raw', keyset.slice(64, 96), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sessionToken = toBase64Url(keyset.slice(96, 128));
  keyset.fill(0);
  return { inputKey, outputKey, proofKey, sessionToken, phonePublicBytes };
}

export async function createApprovalCode(keys, sessionId) {
  const context = encoder.encode(`immich-tv-approval-code-v1|${sessionId}|${toBase64Url(keys.phonePublicBytes)}`);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', keys.proofKey, context));
  const view = new DataView(mac.buffer, mac.byteOffset, mac.byteLength);
  return String(view.getUint32(0, false) % 1000000).padStart(6, '0');
}

export async function encryptOnboardingInput(keys, sessionId, sequence, payload) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const type = 'onboardingInput';
  const aad = encoder.encode(`immich-tv-pairing|1|${sessionId}|phone-to-tv|${sequence}|${type}`);
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({
    name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128,
  }, keys.inputKey, encoder.encode(JSON.stringify(payload))));
  const message = {
    v: 1,
    type,
    sessionId,
    seq: sequence,
    nonce: toBase64Url(nonce),
    ciphertext: toBase64Url(encrypted.slice(0, -16)),
    tag: toBase64Url(encrypted.slice(-16)),
  };
  encrypted.fill(0);
  return message;
}
