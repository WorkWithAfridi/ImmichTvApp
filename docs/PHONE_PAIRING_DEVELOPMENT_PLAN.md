# Phone Pairing and Remote: Development Plan

**Status:** Phone onboarding and the phone remote MVP are code-complete. The TV app now hosts the companion itself over the local network (plain HTTP), so no external deployment is required for the default flow; security review and real-device/release gates remain open.

**Parent research:** [Phone Pairing and Remote R&D](PHONE_PAIRING_REMOTE_RND.md)
**Product goal:** Let a user scan a QR code, enter onboarding details on their phone, and use that phone (or several phones) as a TV remote.

## Current implementation

The detailed milestones below record the original planning and are kept for context; the shipped behavior is summarised here.

- The TV binds an ephemeral LAN HTTP server and serves the bundled `phone_companion/` files itself. The QR points at the TV, so there is no external companion deployment.
- Scanning connects immediately: no TV-side approval screen, verification code, or "Connect" tap on the phone.
- Each phone gets its own token and command sequence. Multiple phones can send setup details or remote commands concurrently; the transport validates order and replays per client.
- Setup details are sent over plain HTTP on the trusted local network. The TV still owns server validation, sign-in, error handling, and secure profile saving.
- A session stays active until the app is backgrounded/stopped, a phone disconnects, or the user revokes it from Settings. "Pair another phone" reuses the active QR.
- Remaining gates: security review of the plain transport, real-device browser/network validation, and release documentation.

## Delivery principles

- Ship phone-assisted setup before the general remote, while designing the pairing/session protocol so both can share it.
- Keep current screen-keyboard and device-keyboard onboarding available through every milestone.
- Keep Immich authentication and profile storage inside the existing app-flow and repository layers.
- Treat the phone as an untrusted client. The TV owns authorization, validation, sign-in, error handling, and session state.
- Do not transfer a password or API key until the selected transport passes the credential security gate.
- Start the network listener only during an explicit pairing/remote session. Do not add background-service behavior to the first release.
- Avoid a cloud dependency unless the product explicitly requires cross-network pairing.

## Milestone overview

Estimates below are engineering effort for one experienced Flutter engineer, excluding device procurement, external security review queue time, release approval, and soak time. The transport decision and device network behavior carry the largest uncertainty; Phase 0 should refine all later estimates.

| Milestone | Outcome | Estimate | Depends on |
| --- | --- | ---: | --- |
| M0. Feasibility spike | Verified TV listener and phone-browser behavior with non-secret data | 2–4 days | None |
| M1. Security and transport decision | Approved threat model, protocol, and architecture decision record | 2–4 days | M0 evidence |
| M2. Pairing protocol foundation | Tested pairing state machine and versioned protocol contract | 3–5 days | M1 |
| M3. TV pairing service and UX | TV can start, approve, cancel, expire, and stop a pairing session | 5–8 days | M2 |
| M4. Phone onboarding page | Phone can submit server URL and either auth form through the approved channel | 4–7 days | M3 |
| M5. Production hardening and pilot | Threat cases, platform permissions, real-device QA, support fallback | 5–9 days | M4 |
| M6. Phone remote MVP | Active paired phone can navigate and control playback | 6–10 days | M5 protocol/session; some UI work may overlap |
| M7. Release and follow-up | Staged rollout, support signals, and go/no-go for persistent pairing | 2–4 days | M5; M6 for remote release |

**Planning range:** roughly 29–51 engineer-days for onboarding plus remote, with a go/no-go after M5 if phone onboarding should ship independently. These are initial sizing estimates, not a date commitment.

## Implementation progress

Development is on `feature/phone-pairing-remote`. The branch contains keyboard improvements, an in-memory TV-hosted session, a local-only plain-HTTP transport, direct connection on scan, multi-phone support, onboarding integration for password and API-key sign-in, and the typed remote-command contract. The legacy encrypted HTTPS transport remains in the protocol/service layer but is not used by the current companion page. The TV retains server validation and sign-in control; the phone does not receive an Immich session.

Milestone status: the pairing and command contracts, TV-hosted listener, onboarding bridge, and phone remote are implemented with automated coverage. The approval UI and encrypted transfer described in M3–M5 belong to the original plan and are superseded by the direct TV-hosted flow above. Real-device QA, platform permission validation, and independent security review remain open. M1's original transport decision is captured in ADR 0001; that ADR describes the superseded HTTPS design.

M6 is code-complete: a `/api/command` route, a TV-side command controller with an app-level action boundary, focus/text/playback adapters, a Settings entry point, and a companion remote page are implemented and covered by tests. The default QR flow now works without external deployment because the TV serves the bundled companion page on its own LAN address. Real-device validation and the M5 security gate are still required before release.

## Trackable milestone breakdown

Treat each `PAIR-###` item as a separately assignable work item. Close a milestone only after its exit criteria below pass. M4 is blocked until M1's credential-transport decision is approved.

### M0 — Feasibility spike

**Milestone outcome:** A supported local connection path is demonstrated with non-secret data on actual hardware.

- **PAIR-001 — TV listener prototype:** Bind an ephemeral listener on Android TV/Google TV and accept one non-secret phone message. **Accept when:** the TV receives the expected payload and the listener stops on cancel/app pause.
- **PAIR-002 — QR and network compatibility report:** Generate a QR/manual address and test Android Chrome, iOS Safari, Wi-Fi, Ethernet, and a blocked/isolated network. **Accept when:** tested device/browser/build versions and failures are recorded; target SDK and permission path are confirmed.

**Milestone gate:** Local reachability is demonstrated on common target hardware, or the team selects a different architecture before production work.

### M1 — Security and transport decision

**Milestone outcome:** A reviewed ADR defines the supported channel for transferring credentials.

- **PAIR-003 — Threat model:** Document LAN interception, page substitution, QR substitution, replay, brute force, lost phone, and TV lifecycle threats. **Accept when:** each threat has a mitigation or an explicitly accepted residual risk.
- **PAIR-004 — Transport ADR:** Compare local page, trusted HTTPS companion, native app, and encrypted relay; choose the first-release path. **Accept when:** page integrity, credential confidentiality, browser permissions/CORS, crypto, offline fallback, and dependencies are decided and reviewed.

**Milestone gate:** No production credential-entry work starts until the ADR states what attacks the channel protects against and what risks remain.

### M2 — Pairing protocol foundation

**Milestone outcome:** Pairing lifecycle and message contract are testable independently of network widgets.

- **PAIR-005 — Versioned protocol and state machine:** Specify messages, pairing/session transitions, request IDs, validation, size limits, and display-safe errors. **Accept when:** invalid, duplicate, expired, and out-of-order messages have defined outcomes.
- **PAIR-006 — Protocol security tests:** Add deterministic clock/entropy seams and tests for expiry, replay, rate limits, revoke, malformed payloads, and invalid transitions. **Accept when:** tests run without sockets and cover every state transition.

**Milestone gate:** The protocol permits only pairing, onboarding input, and the planned typed remote commands; it cannot represent arbitrary Immich API calls.

### M3 — TV pairing service and UX

**Milestone outcome:** TV can start and stop a user-approved pairing session with a non-secret payload.

- **PAIR-007 — Pairing service boundary:** Add injectable service and unsupported-platform behavior. **Accept when:** start, stop, status, and errors can be driven with a fake in widget tests.
- **PAIR-008 — Native listener and address selection:** Implement the approved native transport, usable LAN address/port selection, narrow routes, and lifecycle cleanup. **Accept when:** native smoke tests can connect and the server stops on every terminal path.
- **PAIR-009 — Pairing screen and approval:** Add QR, manual fallback, expiry, accept/deny, cancel, and connection states. **Accept when:** denial, timeout, unsupported platform, and cancel return the user to existing onboarding without trapping focus.

**Milestone gate:** A phone can pair with a non-secret test value; no credential transfer is enabled yet.

### M4 — Phone-assisted onboarding

**Milestone outcome:** Phone submits setup information through the approved channel and TV completes the existing auth flow.

- **PAIR-010 — Companion page:** Build touch-first phone UI with server URL, email/password, and API-key forms. **Accept when:** no third-party scripts, analytics, persistent credential storage, or Immich session display exists.
- **PAIR-011 — Onboarding bridge:** Apply validated phone input to the existing onboarding flow and repository calls. **Accept when:** both auth methods preserve current URL normalization, validation, errors, and secure profile-save behavior.
- **PAIR-012 — Credential lifecycle and regression coverage:** Add acknowledgements, clearing, reconnect/expiry handling, and tests for both phone methods plus existing TV keyboards. **Accept when:** secrets never enter QR/URL/logs/analytics/preferences/browser storage and are cleared after delivery or failure.

**Milestone gate:** M1 security decision is implemented and verified; phone and TV keyboard paths both complete setup successfully.

### M5 — Production hardening and pilot

**Milestone outcome:** Pairing is secure enough for a controlled release and works on the supported TV/phone matrix.

- **PAIR-013 — Permission and network recovery:** Handle Android target-SDK local-network permission, denial, blocked networks, and address changes. **Accept when:** each failure explains how to continue on TV or retry.
- **PAIR-014 — Security review and attack tests:** Test randomness, expiry, brute-force controls, replay, origin/host checks, CSRF, logging/referrer/cache behavior, and revocation. **Accept when:** security review has no unresolved high-severity finding.
- **PAIR-015 — Real-device pilot:** Run supported TV/browser/network and lifecycle matrix; collect privacy-safe failure categories only. **Accept when:** evidence is recorded, support language is ready, and a release go/no-go is documented.

**Milestone gate:** Phone onboarding can ship independently at this point. M6 is not required to release setup assistance.

### M6 — Phone remote MVP

**Milestone outcome:** An active paired phone controls allowlisted TV actions while Immich TV is foregrounded.

- **PAIR-016 — Typed remote command controller:** Add versioned navigation, Select, Back, text, playback, and disconnect commands. **Accept when:** commands map to app-level actions and cannot inject arbitrary keys or invoke arbitrary APIs.
- **PAIR-017 — Remote web UI and session feedback:** Add D-pad, text input, playback controls, TV identity, connected state, and disconnect. **Accept when:** action acknowledgements and network/app disconnect states are clear.
- **PAIR-018 — Remote authorization and QA:** Enforce active-session auth, allowlists, app-state checks, size/rate limits, duplicate suppression, and stale-command rejection. **Accept when:** unpaired, expired, revoked, and malformed clients cannot control the TV, and the real-device remote matrix passes.

**Milestone gate:** Remote-control release checklist is complete; pairing can be revoked immediately from the TV.

### M7 — Release and follow-up

**Milestone outcome:** Feature is releasable, supportable, and has a rollback path.

- **PAIR-019 — Docs and support:** Update packaging/release/development docs, screenshots, known limitations, and fallback instructions. **Accept when:** a tester can follow the setup and troubleshooting guide without internal knowledge.
- **PAIR-020 — Rollout and rollback:** Ship opt-in/staged where available and define disable/rollback steps. **Accept when:** aggregate non-sensitive outcomes can be reviewed and the feature can be disabled without affecting TV keyboard setup.
- **PAIR-021 — Post-release decision:** Review pilot/release feedback before persistent phone trust, mDNS, or relay. **Accept when:** each follow-up is explicitly prioritized or deferred with rationale.

## Dependency path

- **Onboarding critical path:** `PAIR-001` → `PAIR-002` → `PAIR-003` → `PAIR-004` → `PAIR-005` → `PAIR-006` → `PAIR-007` → `PAIR-008` → `PAIR-009` → `PAIR-010` → `PAIR-011` → `PAIR-012` → `PAIR-013` → `PAIR-014` → `PAIR-015`.
- **Remote path:** `PAIR-016` can start after `PAIR-006`; `PAIR-017` can start after `PAIR-009` and the command contract; `PAIR-018` requires `PAIR-015`, `PAIR-016`, and `PAIR-017`.
- **Release path:** `PAIR-019` and `PAIR-020` follow the release scope (onboarding at M5, remote at M6); `PAIR-021` follows pilot/release feedback.

`PAIR-010` and later phone credential work remain blocked by `PAIR-004`'s security decision even though non-secret UI and protocol work can be prepared earlier. The remote command model can be explored after M2, but remote release cannot pass M5's security and device gate.

## Work breakdown

### M0 — Feasibility spike

**Goal:** Prove that the simple local connection works on actual target combinations before building product UI.

1. Create a disposable prototype that binds a native listener on Android TV / Google TV, serves a static page, and accepts a non-secret test message.
2. Display a QR URL generated from the TV's reachable address and listener port; include a manually enterable fallback.
3. Test scan/open/send using Android Chrome and iOS Safari on the same normal Wi-Fi network.
4. Test Wi-Fi and Ethernet, at least two TV vendors, app pause/resume, and at least one isolated/guest network to verify the expected failure mode.
5. Record IPv4 and IPv6 address selection behavior, browser warnings/permissions, port binding, and whether the listener survives app lifecycle transitions.
6. Read the actual Flutter-resolved target SDK from the release build and verify the applicable Android local-network permission path on the target API level.

**Deliverable:** Short findings note with device/browser/build versions, screenshots or logs with no secrets, supported path, known failure cases, and updated estimates.

**Exit gate:** The team can explain the connection path and fallback for each supported phone browser. If the QR local route is blocked on common TV/network combinations, stop and choose a relay or native-app path before production integration.

### M1 — Security and transport decision

1. Write a threat model covering nearby household members, compromised/guest LAN clients, active LAN interception, QR screenshots, malicious origins, replay, brute-force pairing, lost phones, and TV app termination.
2. Compare: (A) TV-hosted local page, (B) trusted HTTPS companion calling a local TV endpoint, (C) native phone client, and (D) encrypted relay.
3. Decide how page integrity and credential confidentiality are achieved. For a hosted HTTPS companion, specify CORS, browser local-network prompts, key agreement, key fingerprint display, ciphertext lifecycle, and outage behavior.
4. Specify pairing approval language so the TV shows the action being approved and the user can deny it.
5. Define whether credentials can be transferred offline. If the approved secure design needs public HTTPS, retain the TV keyboard path as a first-class fallback.
6. Record the choice, rejected options, known limitations, crypto/library dependencies, and Android/iOS/browser permission work in an ADR.

**Deliverable:** Reviewed ADR plus a security checklist signed off before credential fields are sent over the network.

**Exit gate:** No unresolved design relies on raw HTTP while claiming protection against LAN interception or page substitution. If that protection is required and the selected web design cannot provide it, do not ship phone credential entry.

### M2 — Pairing protocol foundation

1. Define protocol types for `pairingStarted`, `pairingRequested`, `pairingApproved`, `inputSubmitted`, `remoteCommand`, `acknowledgement`, `expired`, and `revoked` as applicable to the chosen transport.
2. Version the JSON envelope; add request IDs/sequence numbers, strict payload limits, explicit field allowlists, and error codes safe for display.
3. Implement a pure pairing/session state machine with transitions for start, request, approve, deny, expire, revoke, disconnect, and app lifecycle termination.
4. Add injectable clock and entropy sources so expiry, collision handling, and anti-replay logic can be tested deterministically.
5. Define secret lifetime and redaction rules for logs, crash reports, URL handling, browser storage, and analytics.
6. Add unit tests for malformed messages, duplicate request IDs, expiry boundaries, replay, rejection, revocation, oversized payloads, invalid state transitions, and rate limiting.

**Suggested code boundary:** New `lib/src/features/remote_pairing/` protocol/state files, with interfaces under `lib/src/core/repositories/` only if they are genuinely app-wide abstractions. Keep transport implementation out of widgets.

**Exit gate:** Protocol tests pass without sockets or a live network, and the API cannot represent an arbitrary Immich request or arbitrary URL fetch.

### M3 — TV pairing service and UX

1. Add an injectable pairing service with native and unsupported-platform implementations. Make server startup/stop asynchronous and error-reporting.
2. Implement listener lifecycle, usable-interface selection, random port selection, route limits, allowed host/origin behavior, and exact transport security selected in M1.
3. Add explicit onboarding action to start phone setup; show QR, short/manual fallback, expiry, network help, and cancel.
4. Add TV approval UI with Accept/Deny and a human-readable confirmation value. Permit one pending pairing request in the MVP.
5. Wire lifecycle handling so pairing stops and secrets clear on cancel, backgrounding where required by the approved architecture, success, timeout, failure, and disposal.
6. Expose narrow service status to the UI: starting, waiting for scan, request pending, connected, failed, expired, and unavailable.
7. Add service-level integration tests with a fake transport, then native smoke tests on Android TV hardware.

**Likely touchpoints:** `lib/app.dart`, `lib/src/features/onboarding/onboarding_flow.dart`, `lib/src/features/onboarding/widgets/onboarding_form.dart`, Android manifest/runtime permission handling, and a new pairing feature.

**Exit gate:** The app can pair and disconnect with a non-secret payload. Denial, timeout, and unsupported-platform fallback return cleanly to the existing onboarding methods.

### M4 — Phone-assisted onboarding

1. Build the small responsive phone page with no third-party scripts, telemetry, credential storage, or Immich session display.
2. Provide the server URL step, then email/password and API-key forms. Keep the two auth methods explicit and preserve current Immich terminology.
3. Submit through the approved transport; validate message schema and field size on the TV. Keep validation and auth calls in `OnboardingCubit` / existing repositories.
4. Add acknowledgements so the phone clears credentials after confirmed delivery. Clear fields on page exit, disconnect, and error recovery.
5. Handle phone reload, repeated submit, lost connection, expired pairing, bad server URL, invalid credentials, and API-key permission errors with understandable recovery text.
6. Add onboarding tests for both methods over the paired flow and regressions for the existing screen/device keyboard flows.
7. Verify that no credential appears in logs, QR, URLs, browser storage, test snapshots, telemetry, or app preferences.

**Exit gate:** Both sign-in modes complete with the same user-visible success/error behavior as current onboarding; the TV remains the sole authority for session creation and profile save.

### M5 — Production hardening and pilot

1. Verify cryptographic randomness, single-use pairing secrets, short expiry, rate limits, session revocation, origin/host validation, and replay rejection.
2. Add Android runtime permission handling when required by the target SDK. Verify denial, later grant, and app-settings recovery.
3. Verify network failure reporting for client isolation, guest Wi-Fi, VLANs, VPN, phone cellular fallback, and TV address changes.
4. Test lifecycle behavior: app paused, process killed, TV sleeping, phone suspended, Wi-Fi transition, and route/address change.
5. Review web security headers/CORS as applicable, request logs, crash reporting, URL referrer behavior, cache policy, and credential clearing.
6. Run the full Flutter checks in the repository guidance (`flutter analyze`, `flutter test`) plus release build and device matrix from the R&D doc.
7. Run a small opt-in pilot. Collect only non-sensitive reliability outcomes (stage/result/error category and platform family); never collect field values, QR payloads, tokens, or raw IPs.
8. Triage pilot failures, update user-facing fallback guidance, and make a release go/no-go decision.

**Exit gate:** Security review passes; no high-severity pairing findings remain; critical supported-device/browser combinations pass; all existing onboarding methods still work; release checklist updated.

### M6 — Phone remote MVP

1. Define versioned, typed commands for directional navigation, Select, Back, text edit/clear/submit, playback, and disconnect.
2. Add a TV-side `RemoteCommandController` that maps allowed commands to current app-level actions. Do not inject arbitrary global key events.
3. Add a remote page with clear connection status, TV identity, touch D-pad, text-entry surface, playback controls, and disconnect.
4. Enforce command allowlist, app-state validation, payload limits, rate limits, request IDs, duplicate suppression, and active-session authorization.
5. Add ack/state feedback and reconnect behavior. Expired/revoked sessions must not execute queued commands.
6. Keep the feature foreground-only. When the TV app backgrounds or sleeps, show a clear disconnected/reconnect state.
7. Add tests per command and app state, then execute the full remote device matrix.

**Exit gate:** A paired user can navigate onboarding/home and control supported playback actions; unpaired, expired, revoked, malformed, or unauthorized clients cannot control the TV.

### M6 execution breakdown (phone remote MVP)

These items are ordered so each one is independently testable. The shipped transport is the TV-hosted local session described above; the encrypted M2–M4 design is historical and no longer the default. No relay or raw key injection is introduced.

- [x] **PAIR-016a — Encrypted command transport:** Add a narrow `/api/command` route to `IoPhonePairingService`, reusing the active AEAD session. Accept when: only an active approved session can submit a versioned `remoteCommand`, sequence/replay/body/rate checks run before dispatch, and the phone receives an encrypted acknowledgement that cannot be forged by a LAN observer.
- [x] **PAIR-016b — TV command controller:** Add `RemoteCommandController` with an allowlisted, app-level `RemoteActionHandler` boundary plus `RemotePlaybackRegistry`. Accept when: commands map to narrow handler calls (never arbitrary keys, routes, or Immich APIs), replay/gap/disconnect and out-of-order commands are rejected, and app-background state blocks all commands.
- [x] **PAIR-016c — App action adapter:** Wire focus traversal, activate/back, text insert/backspace/clear/submit, and viewer/slideshow playback into the handler. Accept when: remote navigation moves the real TV focus, text edits land in the focused field, and playback commands reach only a registered active player.
- [x] **PAIR-017a — TV remote session UX:** Add a "Phone remote" entry point that starts a pairing session in remote mode, shows the QR/approval status, then releases the TV UI with a visible connected/disconnected state and an immediate Disconnect action. Accept when: the TV stays usable while paired, and disconnect/revoke works from the TV.
- [x] **PAIR-017b — Companion remote surface:** Extend `phone_companion` with a touch D-pad, Select/Back, text controls, playback controls, TV identity, connection state and Disconnect, driven by the same encrypted session and ack channel. Accept when: each action has visible acknowledgement and expired/revoked/network-disconnected states are clear.
- [x] **PAIR-018a — Authorization and lifecycle hardening:** Stop the session and clear keys on app pause/background/sign-out, enforce per-command rate limits and payload caps, and reject unpaired/expired/revoked/malformed/stale clients. Accept when: no command can execute outside an active foreground session.
- [x] **PAIR-018b — Coverage and docs:** Unit tests for transport, controller, sequence and allowlist; widget tests for the TV remote entry/status; companion crypto/protocol vector updates; README, development checklist, release notes, packaging and release checklist updated. Accept when: `flutter analyze`, `flutter test`, and `npm test --prefix phone_companion` pass with the new coverage.

Real-device QA and a security review of the plain local transport remain separate release gates; completing the items above makes the feature code-complete, not release-ready. Companion deployment is no longer a gate because the TV hosts the page.

### M7 — Release and follow-up

1. Update `docs/ANDROID_TV_PACKAGING.md`, `docs/RELEASE_CHECKLIST.md`, `docs/DEVELOPMENT_CHECKLIST.md`, and release notes with pairing and remote validation.
2. Add setup screenshots and concise support guidance for pairing denial, client isolation, and the on-TV fallback.
3. Ship behind a feature flag or staged rollout if the release infrastructure supports it; otherwise make phone pairing an opt-in action and monitor aggregate failure categories.
4. Review support feedback and reliability data before planning persistent phone trust, mDNS discovery, or relay.

**Exit gate:** Release owner accepts device-test evidence, support instructions, known limitations, and rollback path.

## Definition of done

- [x] A session is initiated only by an explicit TV action, and scanning the QR connects the phone.
- [x] QR/manual fallback, cancel, disconnect, and revoke are implemented and tested.
- [ ] The plain local channel is reviewed against an accepted threat model and used only on trusted networks.
- [ ] Email/password and API-key setup work from the phone and current TV keyboard options.
- [ ] Existing server URL normalization, Immich auth handling, and secure profile persistence remain the source of truth.
- [ ] Pairing values and credentials are ephemeral, excluded from logs/analytics/storage, and cleared after use.
- [ ] Unsupported platforms and blocked networks explain why pairing failed and how to continue on TV.
- [ ] Android target-SDK permission behavior has been tested on a real supported TV build.
- [ ] Automated tests and required real-device/browser evidence are recorded in the release checklist.
- [ ] The feature has a documented rollback/disable path and no unreviewed cloud dependency.

## Out of scope for the first release

- Persistent remembered phones or background wake/control.
- Cloud relay, account system, or remote access across the public internet.
- Bluetooth control or requiring a dedicated phone app.
- Transferring Immich sessions/access tokens to the phone.
- Remote access to Immich APIs, media, settings, or arbitrary app functions.
- Automatic phone discovery with mDNS before QR pairing has been proven reliable.

## Immediate next actions

1. Assign M0 to a Flutter engineer with access to two Android TV / Google TV devices and iOS/Android phones.
2. Capture the resolved release target SDK and identify an API 37 test device/emulator for permission validation.
3. Run the non-secret QR/listener spike and record Android Chrome/iOS Safari results.
4. Hold the M1 security/transport review using those results; do not start phone credential UI before the decision is recorded.
