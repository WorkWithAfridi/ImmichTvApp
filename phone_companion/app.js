import {
  disconnectFromTv,
  pollStatus,
  requestPair,
  sendOnboardingInput,
  sendRemoteCommand,
} from './plain.js';
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

(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const state = {
    invitation: null,
    sessionToken: null,
    sequence: 0,
    sending: false,
    polling: false,
    mode: 'setup',
    remoteActive: false,
    statusTimer: null,
  };
  const continueRemoteButton = $('continueRemoteButton');
  const statusTitle = $('statusTitle');
  const statusMessage = $('statusMessage');
  const statusIcon = $('statusIcon');
  const helpMessage = $('helpMessage');
  const setupForm = $('setupForm');
  const formError = $('formError');
  const sendButton = $('sendButton');
  const remotePanel = $('remotePanel');
  const remoteSession = $('remoteSession');
  const remoteConnection = $('remoteConnection');
  const remoteStatusDot = $('remoteStatusDot');
  const remoteFeedback = $('remoteFeedback');
  const remoteText = $('remoteText');
  const remoteButtons = [...remotePanel.querySelectorAll('button')];

  function setStatus(title, message, icon = '↔') {
    statusTitle.textContent = title;
    statusMessage.textContent = message;
    statusIcon.textContent = icon;
  }

  function readInvitation() {
    const fragment = location.hash.slice(1);
    history.replaceState(null, '', location.pathname);
    const invitation = parseInvitation(fragment);
    let endpoint;
    try {
      endpoint = new URL(invitation.endpoint);
    } catch (_) {
      throw new Error('invalid_invitation');
    }
    if (endpoint.protocol !== 'http:' || endpoint.username || endpoint.password ||
        !(isPrivateIpv4(endpoint.hostname) || endpoint.hostname.endsWith('.local'))) {
      throw new Error('invalid_invitation');
    }
    invitation.endpoint = endpoint.origin;
    state.mode = invitation.mode;
    return invitation;
  }

  function isPrivateIpv4(host) {
    const parts = host.split('.').map(Number);
    if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return false;
    return parts[0] === 10 ||
      (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] === 192 && parts[1] === 168);
  }

  async function requestPairing() {
    // Scanning the QR is the connection: no approval step on either device.
    const response = await requestPair(state.invitation);
    if (response.phase !== 'active' || !response.sessionToken) {
      throw new Error('pairing_rejected');
    }
    state.sessionToken = response.sessionToken;
    if (state.mode === 'remote') {
      enterRemoteMode();
    } else {
      setStatus('Connected', 'Enter your Immich server and sign-in details.', '✓');
      setupForm.hidden = false;
      helpMessage.textContent = 'Keep this page open until the TV confirms.';
    }
  }

  function isTerminalPhase(phase) {
    return phase === 'expired' || phase === 'revoked' || phase === 'stopped';
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
    if (state.sending || !state.sessionToken) return;
    formError.hidden = true;
    if (!setupForm.reportValidity()) return;
    state.sending = true;
    sendButton.disabled = true;
    sendButton.textContent = 'Sending to TV…';
    const method = new FormData(setupForm).get('authMethod');
    const payload = method === 'password'
      ? { v: 1, type: 'onboardingInput', serverUrl: $('serverUrl').value, authMethod: 'password', email: $('email').value, password: $('password').value }
      : { v: 1, type: 'onboardingInput', serverUrl: $('serverUrl').value, authMethod: 'apiKey', apiKey: $('apiKey').value };
    try {
      const response = await sendOnboardingInput(
        state.invitation,
        state.sessionToken,
        ++state.sequence,
        payload,
      );
      // Clear JS references and fields immediately after sending; never persist them.
      payload.password = '';
      payload.apiKey = '';
      payload.email = '';
      payload.serverUrl = '';
      clearCredentials();
      setupForm.hidden = true;
        setStatus('Sent to TV', 'Finish sign-in on the TV. This page has cleared your details.', '✓');
      helpMessage.textContent = response.accepted
        ? 'Close this page, or use this phone as a remote.'
        : 'Continue on the TV.';
      continueRemoteButton.hidden = false;
    } catch (error) {
      clearCredentials();
      formError.hidden = false;
      formError.textContent = error.message === 'tv_http_403'
        ? 'Session expired. Scan a new QR code on the TV.'
        : 'Couldn’t send your details. The fields were cleared. Scan a new QR code to try again, or continue on the TV.';
      sendButton.disabled = false;
      sendButton.textContent = 'Send to TV';
      state.sessionToken = null;
    } finally {
      state.sending = false;
    }
  }

  function setRemoteConnection(label, tone = 'idle') {
    remoteConnection.textContent = label;
    remoteStatusDot.classList.toggle('is-connected', tone === 'connected');
    remoteStatusDot.classList.toggle('is-error', tone === 'error');
  }

  function setRemoteFeedback(text, isError = false) {
    remoteFeedback.textContent = text;
    remoteFeedback.classList.toggle('is-error', isError);
  }

  function setRemoteControlsEnabled(enabled) {
    for (const button of remoteButtons) button.disabled = !enabled;
    remoteText.disabled = !enabled;
  }

  function enterRemoteMode() {
    state.remoteActive = true;
    remotePanel.hidden = false;
    remoteSession.textContent = `Session ${state.invitation.sessionId.slice(0, 6)}`;
    setStatus('Connected', 'Use the controls to navigate and play on your TV.', '✓');
    helpMessage.textContent = 'Keep this page open while connected.';
    setRemoteConnection('Connected', 'connected');
    setRemoteFeedback('Ready');
    setRemoteControlsEnabled(true);
    startStatusPolling();
  }

  function stopStatusPolling() {
    if (state.statusTimer !== null) {
      clearInterval(state.statusTimer);
      state.statusTimer = null;
    }
  }

  function startStatusPolling() {
    stopStatusPolling();
    state.statusTimer = setInterval(pollRemoteStatus, 1500);
  }

  async function pollRemoteStatus() {
    if (state.polling || !state.remoteActive) return;
    state.polling = true;
    try {
      const result = await pollStatus(state.invitation, state.sessionToken);
      if (!state.remoteActive) return;
      if (isTerminalPhase(result.phase)) {
        enterDisconnected(
          result.phase === 'expired' ? 'expired' : result.phase === 'revoked' ? 'revoked' : 'disconnected',
        );
        return;
      }
      if (result.phase === 'active') setRemoteConnection('Connected', 'connected');
      else setRemoteConnection('Disconnected', 'error');
    } catch (_) {
      // A transient network failure must not look like a successful connection.
      if (state.remoteActive) setRemoteConnection('Network error', 'error');
    } finally {
      state.polling = false;
    }
  }

  function enterDisconnected(reason) {
    stopStatusPolling();
    state.remoteActive = false;
    state.sessionToken = null;
    remotePanel.hidden = true;
    remoteText.value = '';
    setRemoteControlsEnabled(false);
    const details = {
      expired: ['Session expired', 'Scan a new QR code on the TV.'],
      revoked: ['Disconnected', 'The TV ended this session. Scan a new QR code.'],
      disconnected: ['Disconnected', 'Scan a new QR code on the TV to reconnect.'],
      networkError: ['Network error', 'Check your connection, then scan a new QR code.'],
    };
    const [title, message] = details[reason] || details.disconnected;
    setStatus(title, message, '!');
    helpMessage.textContent = 'You can always continue with the TV keyboard.';
  }

  async function sendCommand(build) {
    if (state.sending || !state.remoteActive || !state.sessionToken) return null;
    state.sending = true;
    setRemoteControlsEnabled(false);
    setRemoteFeedback('Sending…');
    try {
      // Consume a sequence even if the network fails; a retry must never
      // reuse a number the TV might already have seen.
      const sequence = ++state.sequence;
      const payload = build(sequence);
      const ack = await sendRemoteCommand(
        state.invitation,
        state.sessionToken,
        payload,
      );
      const label = ackFeedback(ack);
      setRemoteFeedback(label, label === 'Failed' || label === 'Unavailable');
      return ack;
    } catch (error) {
      if (error instanceof TypeError || /^tv_http_5/.test(error.message)) {
        setRemoteConnection('Network error', 'error');
      }
      if (error.message === 'tv_http_401' || error.message === 'tv_http_403') {
        enterDisconnected('revoked');
      } else if (state.remoteActive) {
        // Never surface raw error text; it could contain sensitive details.
        setRemoteFeedback('Failed', true);
      }
      return null;
    } finally {
      state.sending = false;
      if (state.remoteActive) setRemoteControlsEnabled(true);
    }
  }

  async function handleCommand(name) {
    if (!state.remoteActive) return;
    let build;
    switch (name) {
      case 'up': build = (seq) => buildNavigateCommand(seq, 'up'); break;
      case 'down': build = (seq) => buildNavigateCommand(seq, 'down'); break;
      case 'left': build = (seq) => buildNavigateCommand(seq, 'left'); break;
      case 'right': build = (seq) => buildNavigateCommand(seq, 'right'); break;
      case 'select': build = buildSelectCommand; break;
      case 'back': build = buildBackCommand; break;
      case 'sendText': {
        // Read at tap time so quick edits are never silently dropped.
        const text = remoteText.value;
        build = (seq) => buildTextInputCommand(seq, text);
        break;
      }
      case 'backspace': build = buildBackspaceCommand; break;
      case 'clearText': build = buildClearTextCommand; break;
      case 'submitText': build = buildSubmitTextCommand; break;
      case 'togglePlayback': build = buildTogglePlaybackCommand; break;
      case 'seekBack': build = (seq) => buildSeekByCommand(seq, -10); break;
      case 'seekForward': build = (seq) => buildSeekByCommand(seq, 10); break;
      case 'disconnect': build = buildDisconnectCommand; break;
      default: return;
    }
    const ack = await sendCommand(build);
    if (ack && name === 'disconnect') {
      try {
        await disconnectFromTv(state.invitation, state.sessionToken);
      } catch (_) {
        // The TV already removed this client when it handled the command.
      }
      enterDisconnected('disconnected');
    }
  }

  function showConnectionError(error) {
    const messages = {
      invalid_invitation: 'This QR code is invalid. Scan a new one from your TV.',
      pairing_expired: 'This TV session expired. Scan a new QR code.',
      pairing_closed: 'The TV closed this session. Scan a new QR code.',
      pairing_rejected: 'The TV could not accept this connection. Scan a new QR code.',
    };
    setStatus('Couldn’t connect', messages[error.message] || 'Check that both devices are on the same Wi‑Fi, then scan a new QR code.', '!');
    helpMessage.textContent = 'You can always continue with the TV keyboard.';
    state.sessionToken = null;
  }

  async function initialize() {
    document.querySelectorAll('input[name="authMethod"]').forEach((input) => input.addEventListener('change', setAuthMode));
    setupForm.addEventListener('submit', submitSetup);
    continueRemoteButton.addEventListener('click', () => {
      if (!state.sessionToken || state.remoteActive) return;
      continueRemoteButton.hidden = true;
      enterRemoteMode();
    });
    remoteButtons.forEach((button) => {
      button.addEventListener('click', () => {
        void handleCommand(button.dataset.command);
      });
    });
    try {
      state.invitation = readInvitation();
      // Scanning the link is the handshake; connect without any button or
      // approval step on either device.
      await requestPairing();
    } catch (error) {
        showConnectionError(error);
    }
    setAuthMode();
    window.addEventListener('pagehide', clearCredentials, { once: true });
  }

  initialize();
})();
