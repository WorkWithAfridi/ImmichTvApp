// Local-only transport for the TV-hosted companion.
//
// The page is served by the TV itself on the same origin as the API. Scanning
// the QR connects immediately; every phone receives its own token and command
// sequence, so several devices can control the TV at once.

async function post(invitation, path, body) {
  const target = new URL(path, invitation.endpoint);
  const response = await fetch(target, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    mode: 'cors',
    credentials: 'omit',
    cache: 'no-store',
    redirect: 'error',
    referrerPolicy: 'no-referrer',
  });
  if (!response.ok) throw new Error(`tv_http_${response.status}`);
  return response.json();
}

export function requestPair(invitation) {
  return post(invitation, '/api/pair', {
    sessionId: invitation.sessionId,
  });
}

export function pollStatus(invitation, sessionToken) {
  return post(invitation, '/api/status', {
    sessionId: invitation.sessionId,
    sessionToken,
  });
}

export function sendOnboardingInput(invitation, sessionToken, sequence, payload) {
  return post(invitation, '/api/input', {
    sessionId: invitation.sessionId,
    sessionToken,
    seq: sequence,
    ...payload,
  });
}

export function sendRemoteCommand(invitation, sessionToken, payload) {
  return post(invitation, '/api/command', {
    sessionId: invitation.sessionId,
    sessionToken,
    ...payload,
  });
}

export function disconnectFromTv(invitation, sessionToken) {
  return post(invitation, '/api/disconnect', {
    sessionId: invitation.sessionId,
    sessionToken,
  });
}
