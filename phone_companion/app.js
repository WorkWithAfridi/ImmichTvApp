import {
  createApprovalCode,
  createPhoneCryptoSession,
  encryptOnboardingInput,
  fromBase64Url,
  toBase64Url,
} from './crypto.js';

(() => {
  'use strict';

  const encoder = new TextEncoder();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const $ = (id) => document.getElementById(id);
  const state = { invitation: null, keys: null, sequence: 0, sending: false };
  const connectButton = $('connectButton');
  const statusTitle = $('statusTitle');
  const statusMessage = $('statusMessage');
  const statusIcon = $('statusIcon');
  const helpMessage = $('helpMessage');
  const verification = $('verification');
  const verificationCode = $('verificationCode');
  const setupForm = $('setupForm');
  const formError = $('formError');
  const sendButton = $('sendButton');

  function setStatus(title, message, icon = '↔') {
    statusTitle.textContent = title;
    statusMessage.textContent = message;
    statusIcon.textContent = icon;
  }

  function readInvitation() {
    const fragment = location.hash.slice(1);
    history.replaceState(null, '', location.pathname);
    const invitation = JSON.parse(decoder.decode(fromBase64Url(fragment)));
    if (invitation.v !== 1 ||
        typeof invitation.sessionId !== 'string' || invitation.sessionId.length > 128 ||
        typeof invitation.bootstrapToken !== 'string' || invitation.bootstrapToken.length < 40 ||
        typeof invitation.endpoint !== 'string' ||
        typeof invitation.tvPublicKey !== 'string') throw new Error('invalid_invitation');
    const endpoint = new URL(invitation.endpoint);
    if (endpoint.protocol !== 'http:' || endpoint.username || endpoint.password ||
        !(isPrivateIpv4(endpoint.hostname) || endpoint.hostname.endsWith('.local'))) {
      throw new Error('invalid_invitation');
    }
    invitation.endpoint = endpoint.origin;
    fromBase64Url(invitation.tvPublicKey);
    return invitation;
  }

  function isPrivateIpv4(host) {
    const parts = host.split('.').map(Number);
    if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;
    return parts[0] === 10 ||
      (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] === 192 && parts[1] === 168);
  }

  function targetFetch(url, options = {}) {
    const request = new Request(url, {
      ...options,
      mode: 'cors',
      credentials: 'omit',
      cache: 'no-store',
      redirect: 'error',
      referrerPolicy: 'no-referrer',
      // Chrome uses this hint to permit a secure page to request a private LAN address.
      targetAddressSpace: 'local',
    });
    return fetch(request);
  }

  async function post(path, body) {
    const response = await targetFetch(`${state.invitation.endpoint}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`tv_http_${response.status}`);
    return response.json();
  }

  async function requestPairing() {
    if (!globalThis.crypto?.subtle) throw new Error('crypto_unavailable');
    const keys = await createPhoneCryptoSession(
      fromBase64Url(state.invitation.tvPublicKey),
      state.invitation.sessionId,
    );
    const code = await createApprovalCode(keys, state.invitation.sessionId);
    const response = await post('/api/pair', {
      sessionId: state.invitation.sessionId,
      bootstrapToken: state.invitation.bootstrapToken,
      phonePublicKey: toBase64Url(keys.phonePublicBytes),
    });
    if (response.phase !== 'approvalPending') throw new Error('pairing_rejected');
    state.keys = keys;
    verificationCode.textContent = code;
    verification.hidden = false;
    setStatus('Check the code on your TV', 'Make sure the six-digit code below matches the one shown on your TV. Approve only if the codes match.', '✓');
    connectButton.hidden = true;
    helpMessage.textContent = 'Waiting for approval on your TV…';
    await waitForApproval();
  }

  async function waitForApproval() {
    while (true) {
      await new Promise((resolve) => setTimeout(resolve, 1200));
      const result = await post('/api/status', { sessionId: state.invitation.sessionId });
      if (result.phase === 'active') {
        setStatus('You’re connected', 'Enter your Immich server and sign-in details below. Your credentials are encrypted on this phone.', '✓');
        setupForm.hidden = false;
        helpMessage.textContent = 'Keep this page open until the TV confirms your details were received.';
        return;
      }
      if (result.phase === 'expired' || result.phase === 'revoked' || result.phase === 'stopped') {
        throw new Error(result.phase === 'expired' ? 'pairing_expired' : 'pairing_closed');
      }
    }
  }

  function setAuthMode() {
    const method = new FormData(setupForm).get('authMethod');
    $('passwordFields').hidden = method !== 'password';
    $('apiKeyFields').hidden = method !== 'apiKey';
    $('email').required = method === 'password';
    $('password').required = method === 'password';
    $('apiKey').required = method === 'apiKey';
  }

  function clearCredentials() {
    $('password').value = '';
    $('apiKey').value = '';
    $('email').value = '';
    $('serverUrl').value = '';
  }

  async function submitSetup(event) {
    event.preventDefault();
    if (state.sending || !state.keys) return;
    formError.hidden = true;
    if (!setupForm.reportValidity()) return;
    state.sending = true;
    sendButton.disabled = true;
    sendButton.textContent = 'Encrypting and sending…';
    const method = new FormData(setupForm).get('authMethod');
    const payload = method === 'password'
      ? { v: 1, type: 'onboardingInput', serverUrl: $('serverUrl').value, authMethod: 'password', email: $('email').value, password: $('password').value }
      : { v: 1, type: 'onboardingInput', serverUrl: $('serverUrl').value, authMethod: 'apiKey', apiKey: $('apiKey').value };
    try {
      const encrypted = await encryptOnboardingInput(
        state.keys,
        state.invitation.sessionId,
        ++state.sequence,
        payload,
      );
      // Clear JS references and fields immediately after encryption; never persist them.
      payload.password = '';
      payload.apiKey = '';
      payload.email = '';
      payload.serverUrl = '';
      const response = await post('/api/input', encrypted);
      clearCredentials();
      setupForm.hidden = true;
      verification.hidden = true;
      setStatus('Details sent to your TV', 'Finish server validation and sign-in on the TV screen. This page has cleared the details you entered.', '✓');
      helpMessage.textContent = response.accepted ? 'You can close this page now.' : 'Continue on the TV to complete setup.';
      state.keys = null;
    } catch (error) {
      clearCredentials();
      formError.hidden = false;
      formError.textContent = error.message === 'tv_http_403'
        ? 'The pairing was not approved or has expired. Start a new phone pairing from your TV.'
        : 'We could not send these details. For your safety, the fields were cleared. Start a new phone pairing and try again, or continue on the TV.';
      sendButton.disabled = false;
      sendButton.textContent = 'Send setup details to TV';
      state.keys = null;
    } finally {
      state.sending = false;
    }
  }

  function showConnectionError(error) {
    const messages = {
      invalid_invitation: 'This pairing link is invalid. Scan a new code from your TV.',
      crypto_unavailable: 'This browser does not support the secure pairing required. Update your browser or continue setup on the TV.',
      pairing_expired: 'This pairing request expired. Start a new request on the TV.',
      pairing_closed: 'This pairing request was closed on the TV.',
      pairing_rejected: 'The TV could not accept this pairing request. Start a new one from the TV.',
    };
    setStatus('Could not connect', messages[error.message] || 'Check that both devices are on the same network and allow this page to connect to local devices. Then scan a new code.', '!');
    connectButton.hidden = true;
    helpMessage.textContent = 'Guest Wi-Fi, router isolation, or browser local-network settings can block the connection. Your TV keyboard is always available.';
    state.keys = null;
  }

  function initialize() {
    document.querySelectorAll('input[name="authMethod"]').forEach((input) => input.addEventListener('change', setAuthMode));
    setupForm.addEventListener('submit', submitSetup);
    connectButton.addEventListener('click', async () => {
      connectButton.disabled = true;
      connectButton.textContent = 'Connecting…';
      try {
        await requestPairing();
      } catch (error) {
        showConnectionError(error);
      }
    });
    try {
      state.invitation = readInvitation();
      if (!globalThis.crypto?.subtle) throw new Error('crypto_unavailable');
    } catch (error) {
      connectButton.hidden = true;
      showConnectionError(error);
    }
    setAuthMode();
    window.addEventListener('pagehide', clearCredentials, { once: true });
  }

  initialize();
})();
