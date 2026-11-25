# ADR 0001: Phone credential transport

- **Status:** Accepted for implementation; browser and device validation remain open
- **Date:** 2026-11-25
- **Decision owners:** Immich TV maintainers

## Context

Phone setup needs to submit a server URL and either an email/password pair or an API key to the TV. The TV can only be reached over the local network in the first release. A local HTTP page is not trustworthy: an active LAN attacker can replace the JavaScript and capture credentials before any payload encryption. A local TLS certificate is not a good browser UX because it is not issued by a public trust anchor and browsers do not let a page bypass the certificate warning safely.

The phone browser also cannot depend on Bluetooth. A public HTTPS page calling a private TV IP is a cross-origin local-network request; browsers can gate it behind user permission and CORS. Chrome's current guidance requires a secure context and an explicit user gesture for this flow. Android apps targeting API 37 need the local-network runtime permission to accept incoming TCP connections.

## Decision

Use a small, static companion page served from a maintainer-controlled HTTPS origin. It connects directly to the TV's ephemeral local HTTP endpoint. The QR contains the companion URL and a one-time bootstrap payload in the URL fragment. The bootstrap payload includes the TV address/port, pairing ID, bootstrap capability, protocol version, and the TV's ephemeral P-256 ECDH public key.

The TV keeps its ECDH private key in memory. After scanning, the phone generates a fresh P-256 key pair and sends its public key with the one-time bootstrap capability. Both sides derive the same session key with ECDH P-256, HKDF-SHA-256, and AES-256-GCM. Associated data binds protocol version, pairing ID, direction, and monotonically increasing sequence. Every credential-bearing message is encrypted on the phone before it reaches the LAN. The TV derives the same key, verifies the AEAD tag, validates the message schema, and forwards the values only to the existing onboarding flow.

The phone and TV each compute a short verification code from the derived session key and pairing ID. The phone displays its code; the TV displays its independently computed code and requires explicit approval. A code mismatch, denied request, expired session, malformed key, invalid tag, replay, or sequence gap fails closed. Approval is not implied by scanning. Session keys, decrypted values, and onboarding buffers stay in memory and are cleared on submit, failure, cancel, expiry, or lifecycle termination.

The same derived key protects the acknowledgement and subsequent typed remote commands. The TV continues to own validation, Immich sign-in, error messages, session storage, and remote authorization. There is no credential relay service.

## Security properties and limits

- HTTPS protects the companion code from network modification between the phone and the configured web origin.
- The QR-pinned TV public key and key-derived verification code detect an endpoint/key substitution or modified key exchange, provided the user scans the code displayed by their TV and compares the codes before approval.
- ECDH plus HKDF and AES-GCM protect credential and remote payload confidentiality and integrity against passive LAN observers and active message tampering.
- The one-time bootstrap capability is a pairing locator, not an Immich credential. Exposure can enable a pairing race or denial of service, but does not reveal the derived key or plaintext credentials.
- This does not protect a compromised phone/browser, compromised companion origin or its deployment pipeline, a user approving a mismatched code, or a malicious TV. The companion origin is security-critical and must be controlled accordingly.
- The browser may prompt for local-network access, and some phone/browser/network combinations may deny or block the direct connection. TV keyboard entry remains a first-class fallback.
- ECDH public key serialization, HKDF salt/info, AES-GCM nonce format, AAD encoding, proof-code derivation, and message schemas must be specified once and tested cross-language before credential fields are enabled. Do not substitute custom cryptographic primitives or ad hoc encodings.

## Alternatives considered

1. **TV-served local HTTP page:** rejected for credentials because an active LAN attacker can replace the JavaScript.
2. **Locally generated HTTPS certificate:** rejected for consumer browser UX because the certificate is not publicly trusted; QR pinning alone does not make browsers accept the page as a secure origin.
3. **Public HTTPS page without payload encryption:** rejected because the TV local endpoint is HTTP and LAN observers can read credentials.
4. **Cloud relay:** deferred. It adds service operations and privacy exposure without being necessary for same-network onboarding.
5. **Native phone app or Bluetooth:** deferred because they add install/maintenance friction and do not improve the first-release web experience enough to justify that cost.

## Implementation requirements

1. Host only static companion assets at an HTTPS origin under maintainer control. Do not load third-party scripts, fonts, analytics, or remote form services.
2. Add a restrictive CSP, no-store policy, no-referrer policy, and no service worker/cache for the credential route. Never put credentials in URLs, storage, logs, telemetry, or crash reports.
3. Require an explicit phone gesture before the first local-network request. Implement exact CORS allowlisting for the configured origin, a narrow `OPTIONS` response, exact Host validation, strict content types, body limits, and no wildcard origins.
4. Use the audited `cryptography` Dart package's P-256 ECDH, HKDF, and AES-GCM APIs plus Web Crypto on the browser. Keep algorithms and encodings pinned in a versioned protocol and verify cross-language test vectors.
5. Permit credential submission only after explicit TV approval and successful authentication of the active session. Do not return Immich tokens, profile secrets, or server responses to the phone.
6. Keep HTTP pairing preview non-secret-only until the secure companion origin and encrypted protocol are configured. Do not label the existing HTTP preview secure.
7. Validate on Android Chrome and iOS Safari, including local-network permission prompts, CORS preflight, credential round trips, network denial, and failure fallback before release.

## Consequences

This keeps the no-install QR experience and avoids a cloud credential relay, but requires maintaining a public HTTPS companion asset and testing browser local-network permissions. Phone entry is unavailable when the phone cannot load the trusted HTTPS origin or reach the TV on the LAN. The existing keyboard paths remain available in those cases.

## References

- [Chrome Local Network Access guidance](https://developer.chrome.com/docs/modern-web-guidance/guides/security/local-network-access)
- [Web Crypto `SubtleCrypto.deriveKey()`](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/deriveKey)
- [`cryptography` Dart package](https://pub.dev/packages/cryptography)
- [Android local-network permission](https://developer.android.com/privacy-and-security/local-network-permission)
