import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  createApprovalCode,
  decryptFromTv,
  derivePhoneCryptoSession,
  encryptRemoteCommand,
  fromBase64Url,
  toBase64Url,
} from './crypto.js';
import { buildNavigateCommand } from './commands.js';

const vector = JSON.parse(await readFile(new URL('./crypto_test_vectors.json', import.meta.url), 'utf8'));
const hex = (value) => Uint8Array.from(Buffer.from(value, 'hex'));
const alice = {
  kty: 'OKP', crv: 'X25519',
  d: Buffer.from('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a', 'hex').toString('base64url'),
  x: vector.tvPublic, ext: true, key_ops: ['deriveBits'],
};
const bob = {
  kty: 'OKP', crv: 'X25519',
  d: Buffer.from('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb', 'hex').toString('base64url'),
  x: vector.phonePublic, ext: true, key_ops: ['deriveBits'],
};

test('Web Crypto matches the shared X25519, HKDF, approval, and AES-GCM vector', async () => {
  const privateKey = await crypto.subtle.importKey('jwk', bob, { name: 'X25519' }, false, ['deriveBits']);
  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { kty: 'OKP', crv: 'X25519', x: bob.x, ext: true, key_ops: [] },
    { name: 'X25519' },
    false,
    [],
  );
  const keys = await derivePhoneCryptoSession(
    fromBase64Url(vector.tvPublic),
    vector.sessionId,
    { privateKey, publicKey },
    fromBase64Url(vector.phonePublic),
  );

  assert.equal(keys.sessionToken, vector.sessionToken);
  assert.equal(await createApprovalCode(keys, vector.sessionId), vector.approvalCode);

  const nonce = fromBase64Url(vector.nonce);
  const aad = new TextEncoder().encode(
    `immich-tv-pairing|1|${vector.sessionId}|phone-to-tv|${vector.sequence}|${vector.type}`,
  );
  const encrypted = new Uint8Array(await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128 },
    keys.inputKey,
    new TextEncoder().encode(vector.plaintext),
  ));

  assert.equal(toBase64Url(encrypted.slice(0, -16)), vector.ciphertext);
  assert.equal(toBase64Url(encrypted.slice(-16)), vector.tag);
});

test('the interoperability vector uses the RFC 7748 public key values', () => {
  assert.deepEqual(fromBase64Url(vector.tvPublic), hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a'));
  assert.deepEqual(fromBase64Url(vector.phonePublic), hex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f'));
  assert.equal(alice.crv, 'X25519');
});

test('rejects a low-order all-zero TV public key', async () => {
  const privateKey = await crypto.subtle.importKey('jwk', bob, { name: 'X25519' }, false, ['deriveBits']);
  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { kty: 'OKP', crv: 'X25519', x: bob.x, ext: true, key_ops: [] },
    { name: 'X25519' },
    false,
    [],
  );
  await assert.rejects(
    derivePhoneCryptoSession(new Uint8Array(32), vector.sessionId, { privateKey, publicKey }, fromBase64Url(vector.phonePublic)),
    /invalid_public_key/,
  );
});

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder('utf-8', { fatal: true });

async function phoneSession() {
  const privateKey = await crypto.subtle.importKey('jwk', bob, { name: 'X25519' }, false, ['deriveBits']);
  const publicKey = await crypto.subtle.importKey(
    'jwk',
    { kty: 'OKP', crv: 'X25519', x: bob.x, ext: true, key_ops: [] },
    { name: 'X25519' },
    false,
    [],
  );
  return derivePhoneCryptoSession(
    fromBase64Url(vector.tvPublic),
    vector.sessionId,
    { privateKey, publicKey },
    fromBase64Url(vector.phonePublic),
  );
}

// Re-derive the TV-to-phone AES key so the test can produce an ack exactly as
// the TV does, without exposing extra key material from crypto.js.
async function deriveKeyset() {
  const alicePrivate = await crypto.subtle.importKey('jwk', alice, { name: 'X25519' }, false, ['deriveBits']);
  const bobPublic = await crypto.subtle.importKey(
    'jwk',
    { kty: 'OKP', crv: 'X25519', x: vector.phonePublic, ext: true, key_ops: [] },
    { name: 'X25519' },
    false,
    [],
  );
  const shared = new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'X25519', public: bobPublic }, alicePrivate, 256,
  ));
  const hkdfMaterial = await crypto.subtle.importKey('raw', shared, 'HKDF', false, ['deriveBits']);
  const keyset = new Uint8Array(await crypto.subtle.deriveBits({
    name: 'HKDF', hash: 'SHA-256',
    salt: textEncoder.encode(`immich-tv-pairing-v1:${vector.sessionId}`),
    info: textEncoder.encode('immich-tv-session-keyset-v1'),
  }, hkdfMaterial, 1024));
  assert.equal(toBase64Url(keyset.slice(96, 128)), vector.sessionToken);
  return keyset;
}

async function tvToPhoneEncryptKey() {
  const keyset = await deriveKeyset();
  return crypto.subtle.importKey('raw', keyset.slice(32, 64), { name: 'AES-GCM' }, false, ['encrypt']);
}

async function phoneToTvDecryptKey() {
  const keyset = await deriveKeyset();
  return crypto.subtle.importKey('raw', keyset.slice(0, 32), { name: 'AES-GCM' }, false, ['decrypt']);
}

async function encryptAckFromTv(ack, direction = 'tv-to-phone') {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const aad = textEncoder.encode(
    `immich-tv-pairing|1|${vector.sessionId}|${direction}|${ack.seq}|ack`,
  );
  const encrypted = new Uint8Array(await crypto.subtle.encrypt({
    name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128,
  }, await tvToPhoneEncryptKey(), textEncoder.encode(JSON.stringify(ack))));
  return {
    v: 1,
    type: 'ack',
    sessionId: vector.sessionId,
    seq: ack.seq,
    nonce: toBase64Url(nonce),
    ciphertext: toBase64Url(encrypted.slice(0, -16)),
    tag: toBase64Url(encrypted.slice(-16)),
  };
}

test('remote commands encrypt with the phone-to-tv key and strict envelope', async () => {
  const keys = await phoneSession();
  const command = buildNavigateCommand(9, 'up');
  const message = await encryptRemoteCommand(keys, vector.sessionId, 9, command);
  assert.deepEqual(Object.keys(message).sort(), [
    'ciphertext', 'nonce', 'seq', 'sessionId', 'tag', 'type', 'v',
  ]);
  assert.equal(message.v, 1);
  assert.equal(message.type, 'remoteCommand');
  assert.equal(message.sessionId, vector.sessionId);
  assert.equal(message.seq, 9);

  const sealed = new Uint8Array([
    ...fromBase64Url(message.ciphertext), ...fromBase64Url(message.tag),
  ]);
  const aad = textEncoder.encode(
    `immich-tv-pairing|1|${vector.sessionId}|phone-to-tv|9|remoteCommand`,
  );
  const plaintext = new Uint8Array(await crypto.subtle.decrypt({
    name: 'AES-GCM', iv: fromBase64Url(message.nonce), additionalData: aad, tagLength: 128,
  }, await phoneToTvDecryptKey(), sealed));
  assert.deepEqual(JSON.parse(textDecoder.decode(plaintext)), command);
});

test('ack round trip succeeds and tampered envelopes are rejected', async () => {
  const keys = await phoneSession();
  const ack = { v: 1, type: 'ack', seq: 10, accepted: true, outcome: 'ok' };
  const message = await encryptAckFromTv(ack);
  assert.deepEqual(await decryptFromTv(keys, message, vector.sessionId), ack);

  const tamperedTag = fromBase64Url(message.tag);
  tamperedTag[0] ^= 1;
  await assert.rejects(
    decryptFromTv(keys, { ...message, tag: toBase64Url(tamperedTag) }, vector.sessionId),
    /invalid_message/,
  );
  await assert.rejects(
    decryptFromTv(keys, { ...message, seq: message.seq + 1 }, vector.sessionId),
    /invalid_message/,
  );
  await assert.rejects(
    decryptFromTv(keys, { ...message, type: 'status' }, vector.sessionId),
    /invalid_message/,
  );
  await assert.rejects(
    decryptFromTv(keys, message, 'another-session'),
    /invalid_message/,
  );
  await assert.rejects(
    decryptFromTv(keys, await encryptAckFromTv(ack, 'phone-to-tv'), vector.sessionId),
    /invalid_message/,
  );
});

