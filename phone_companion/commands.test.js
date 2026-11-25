import assert from 'node:assert/strict';
import test from 'node:test';
import {
  ackFeedback,
  buildBackCommand,
  buildBackspaceCommand,
  buildClearTextCommand,
  buildDisconnectCommand,
  buildNavigateCommand,
  buildSeekByCommand,
  buildSelectCommand,
  buildSubmitTextCommand,
  buildTextInputCommand,
  buildTogglePlaybackCommand,
  parseInvitation,
} from './commands.js';
import { toBase64Url } from './crypto.js';

const encodeFragment = (value) => toBase64Url(new TextEncoder().encode(JSON.stringify(value)));
const baseInvitation = {
  v: 1,
  sessionId: 'session-abc123',
  bootstrapToken: 'x'.repeat(48),
  endpoint: 'http://192.168.1.10:1234',
  tvPublicKey: 'AQID',
};

test('invitation mode defaults to setup for QR codes without the field', () => {
  assert.equal(parseInvitation(encodeFragment(baseInvitation)).mode, 'setup');
});

test('invitation mode accepts setup and remote', () => {
  assert.equal(parseInvitation(encodeFragment({ ...baseInvitation, mode: 'setup' })).mode, 'setup');
  const parsed = parseInvitation(encodeFragment({ ...baseInvitation, mode: 'remote' }));
  assert.equal(parsed.mode, 'remote');
  assert.equal(parsed.sessionId, baseInvitation.sessionId);
  assert.deepEqual(Object.keys(parsed).sort(), [
    'endpoint', 'mode', 'sessionId', 'v',
  ]);
});

test('invitation rejects unknown modes and malformed fragments', () => {
  for (const mode of ['admin', 'SETUP', 'remote ', '', null, 1, [], {}]) {
    assert.throws(() => parseInvitation(encodeFragment({ ...baseInvitation, mode })), /invalid_invitation/);
  }
  assert.throws(() => parseInvitation('!!!'), /invalid_invitation/);
  assert.throws(() => parseInvitation(toBase64Url(new TextEncoder().encode('{'))), /invalid_invitation/);
  assert.throws(() => parseInvitation(encodeFragment({ ...baseInvitation, v: 2 })), /invalid_invitation/);
  assert.equal(
    parseInvitation(encodeFragment({
      v: 1,
      sessionId: 'tv-hosted',
      endpoint: 'http://192.168.0.172:43593',
      mode: 'remote',
    })).mode,
    'remote',
  );
});

test('command builders emit the exact strict key sets expected by RemoteCommand.fromJson', () => {
  const cases = [
    [buildNavigateCommand(3, 'up'), { v: 1, type: 'remoteCommand', seq: 3, command: 'navigate', direction: 'up' }],
    [buildNavigateCommand(4, 'down'), { v: 1, type: 'remoteCommand', seq: 4, command: 'navigate', direction: 'down' }],
    [buildNavigateCommand(5, 'left'), { v: 1, type: 'remoteCommand', seq: 5, command: 'navigate', direction: 'left' }],
    [buildNavigateCommand(6, 'right'), { v: 1, type: 'remoteCommand', seq: 6, command: 'navigate', direction: 'right' }],
    [buildSelectCommand(7), { v: 1, type: 'remoteCommand', seq: 7, command: 'select' }],
    [buildBackCommand(8), { v: 1, type: 'remoteCommand', seq: 8, command: 'back' }],
    [buildTextInputCommand(9, 'hello'), { v: 1, type: 'remoteCommand', seq: 9, command: 'textInput', text: 'hello' }],
    [buildBackspaceCommand(10), { v: 1, type: 'remoteCommand', seq: 10, command: 'backspace' }],
    [buildClearTextCommand(11), { v: 1, type: 'remoteCommand', seq: 11, command: 'clearText' }],
    [buildSubmitTextCommand(12), { v: 1, type: 'remoteCommand', seq: 12, command: 'submitText' }],
    [buildTogglePlaybackCommand(13), { v: 1, type: 'remoteCommand', seq: 13, command: 'togglePlayback' }],
    [buildSeekByCommand(14, -10), { v: 1, type: 'remoteCommand', seq: 14, command: 'seekBy', seconds: -10 }],
    [buildSeekByCommand(15, 60), { v: 1, type: 'remoteCommand', seq: 15, command: 'seekBy', seconds: 60 }],
    [buildDisconnectCommand(16), { v: 1, type: 'remoteCommand', seq: 16, command: 'disconnect' }],
  ];
  for (const [actual, expected] of cases) {
    assert.deepEqual(actual, expected);
    assert.deepEqual(Object.keys(actual).sort(), Object.keys(expected).sort());
  }
});

test('command builders reject out-of-contract values', () => {
  assert.throws(() => buildNavigateCommand(1, 'diagonal'), /invalid_command/);
  assert.throws(() => buildTextInputCommand(1, ''), /invalid_command/);
  assert.throws(() => buildTextInputCommand(1, 'a'.repeat(257)), /invalid_command/);
  assert.throws(() => buildSeekByCommand(1, 0), /invalid_command/);
  assert.throws(() => buildSeekByCommand(1, 61), /invalid_command/);
  assert.throws(() => buildSeekByCommand(1, 1.5), /invalid_command/);
  assert.throws(() => buildSelectCommand(0), /invalid_command/);
  assert.throws(() => buildBackCommand(-1), /invalid_command/);
  assert.throws(() => buildBackCommand(1.5), /invalid_command/);
});

test('ack feedback maps accepted and outcome without exposing error text', () => {
  assert.equal(ackFeedback({ v: 1, type: 'ack', seq: 1, accepted: true, outcome: 'ok' }), 'Sent');
  assert.equal(ackFeedback({ v: 1, type: 'ack', seq: 1, accepted: true, outcome: 'unavailable' }), 'Not available on TV');
  assert.equal(ackFeedback({ v: 1, type: 'ack', seq: 1, accepted: false, outcome: 'invalid' }), 'Failed');
  assert.equal(ackFeedback({ v: 1, type: 'ack', seq: 1, accepted: false, outcome: 'ignored' }), 'Ignored on TV');
  assert.throws(() => ackFeedback({ v: 1, type: 'ack', seq: 1, accepted: true, outcome: 'unknown' }), /invalid_ack/);
});
