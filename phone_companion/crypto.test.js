import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  createApprovalCode,
  derivePhoneCryptoSession,
  fromBase64Url,
  toBase64Url,
} from './crypto.js';

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
