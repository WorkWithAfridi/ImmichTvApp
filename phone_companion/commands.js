// Pure, DOM-free helpers shared by app.js and the node test suite.
// Keep the plaintext command shapes in sync with the TV's RemoteCommand.fromJson
// (lib/src/features/remote_pairing/remote_command.dart): it rejects any extra or
// missing key, so these builders are the only place commands are constructed.
import { fromBase64Url } from './crypto.js';

const decoder = new TextDecoder('utf-8', { fatal: true });
const directions = new Set(['up', 'down', 'left', 'right']);
const outcomes = new Set(['ok', 'ignored', 'unavailable', 'invalid']);

export function parseInvitation(fragment) {
  let invitation;
  try {
    invitation = JSON.parse(decoder.decode(fromBase64Url(fragment)));
  } catch (_) {
    throw new Error('invalid_invitation');
  }
  if (!invitation || typeof invitation !== 'object' || Array.isArray(invitation) ||
      invitation.v !== 1 ||
      typeof invitation.sessionId !== 'string' || invitation.sessionId.length > 128 ||
      typeof invitation.endpoint !== 'string') {
    throw new Error('invalid_invitation');
  }
  // Older QR codes include bootstrapToken/tvPublicKey; TV-hosted codes do not.
  const mode = invitation.mode === undefined ? 'setup' : invitation.mode;
  if (mode !== 'setup' && mode !== 'remote') throw new Error('invalid_invitation');
  return {
    v: 1,
    sessionId: invitation.sessionId,
    endpoint: invitation.endpoint,
    mode,
  };
}

function base(sequence, command) {
  if (!Number.isSafeInteger(sequence) || sequence < 1) throw new Error('invalid_command');
  return { v: 1, type: 'remoteCommand', seq: sequence, command };
}

export function buildNavigateCommand(sequence, direction) {
  if (!directions.has(direction)) throw new Error('invalid_command');
  return { ...base(sequence, 'navigate'), direction };
}

export function buildSelectCommand(sequence) {
  return base(sequence, 'select');
}

export function buildBackCommand(sequence) {
  return base(sequence, 'back');
}

export function buildTextInputCommand(sequence, text) {
  if (typeof text !== 'string' || text.length === 0 || text.length > 256) {
    throw new Error('invalid_command');
  }
  return { ...base(sequence, 'textInput'), text };
}

export function buildBackspaceCommand(sequence) {
  return base(sequence, 'backspace');
}

export function buildClearTextCommand(sequence) {
  return base(sequence, 'clearText');
}

export function buildSubmitTextCommand(sequence) {
  return base(sequence, 'submitText');
}

export function buildTogglePlaybackCommand(sequence) {
  return base(sequence, 'togglePlayback');
}

export function buildSeekByCommand(sequence, seconds) {
  if (!Number.isSafeInteger(seconds) || seconds === 0 || Math.abs(seconds) > 60) {
    throw new Error('invalid_command');
  }
  return { ...base(sequence, 'seekBy'), seconds };
}

export function buildDisconnectCommand(sequence) {
  return base(sequence, 'disconnect');
}

export function ackFeedback(ack) {
  if (!ack || typeof ack !== 'object' || Array.isArray(ack) ||
      ack.v !== 1 || ack.type !== 'ack' ||
      !Number.isSafeInteger(ack.seq) || ack.seq < 1 ||
      typeof ack.accepted !== 'boolean' || !outcomes.has(ack.outcome)) {
    throw new Error('invalid_ack');
  }
  if (ack.outcome === 'unavailable') return 'Unavailable';
  if (ack.outcome === 'ignored') return 'Ignored';
  if (ack.outcome === 'invalid') return 'Failed';
  return ack.accepted ? 'Sent' : 'Failed';
}
