# Phone Pairing and Remote: R&D and Delivery Plan

**Status:** TV-hosted local companion implemented; phone onboarding and phone remote MVP complete; security review and device/release gates remain open

## Current implementation

The shipped flow is intentionally simpler than the original recommendation below: the TV hosts the companion page itself on its LAN address, scanning the QR connects the phone immediately, and multiple phones can control the TV concurrently. The transport is plain HTTP on the trusted local network; it is not encrypted and is not described as secure credential transport. The TV remains the authority for server validation, sign-in, and profile saving. The original R&D notes and ADR 0001 describe the superseded HTTPS-encrypted option and are retained for context.

**Product target:** Android TV / Google TV first; browser-based phone companion

**Scope:** Phone-assisted onboarding now, extensible to a phone remote later

For sequenced work packages, estimates, dependencies, and exit criteria, see the [development plan](PHONE_PAIRING_DEVELOPMENT_PLAN.md).

[ADR 0001](adr/0001-phone-credential-transport.md) records the original HTTPS-with-encryption decision. The implemented flow uses the TV-hosted local option instead; browser/device validation and independent security review remain release gates.

## Recommendation

Build toward a QR-paired, same-network web companion served by or connected directly to the TV app. Use it first to enter the Immich server URL and credentials during onboarding. Evolve the same pairing and transport into a remote-control surface for text entry, navigation, and playback.

Do not use Bluetooth as the primary transport. A phone browser cannot depend on Web Bluetooth across major mobile browsers, and Bluetooth would still require discovery, permissions, pairing, and a separate command protocol. Bluetooth does not solve the session-authentication problem.

There is one release gate before transferring passwords or API keys: implement and validate the selected transport security model. A local HTTP page is simple and self-hosted, but it does not protect credentials from an active attacker on the LAN who can replace the page or intercept traffic. Pairing approval and a short-lived QR token reduce unauthorized pairing; they do not make HTTP a confidential, authenticated channel. Do not describe that design as secure credential transport.

Recommended decision sequence:

1. Prototype local server reachability and browser behavior on target hardware with non-secret test data.
2. Implemented transport: a TV-hosted companion on a narrowly scoped LAN endpoint with per-phone tokens and sequence checks. The original HTTPS encrypted design in this document is historical.
3. Only enable phone credential entry after a threat-model review and security tests pass.
4. Reuse the approved pairing session for a remote-control protocol; keep pairing and remote authorization distinct from Immich authentication.

The QR code is a bootstrap for a local control session. It must never contain an Immich password, API key, or Immich access token.

## Current codebase context

- The app is Flutter/Dart, uses `flutter_bloc`, and targets Android TV while also building for web, desktop, and mobile.
- App startup and repository injection live in `lib/app.dart`; `lib/src/app_shell.dart` switches between bootstrap, profile picker, onboarding, and home.
- Onboarding is implemented in `lib/src/features/onboarding/onboarding_flow.dart`, with UI in `lib/src/features/onboarding/widgets/onboarding_form.dart` and state in `lib/src/features/onboarding/cubit/`.
- Current setup order is input-method selection → server URL validation → auth-method selection → email/password or API-key sign-in → optional PIN → profile save.
- Authentication uses the `AuthRepository` interface. `ImmichAuthRepository` performs the server login and `/users/me` verification. Profile metadata is stored separately from secrets; production integration must continue using secure storage for saved credentials.
- Network access for the library is outbound Dio traffic through `ImmichDioFactory`. Phone setup/remote adds an ephemeral LAN HTTP server in `IoPhonePairingService`; it serves the bundled companion files and a narrow set of JSON endpoints.
- Android release manifest already declares `INTERNET`. Its `usesCleartextTraffic` setting exists for users whose Immich servers use local HTTP; that setting does not itself provide TLS or authenticate a new inbound control server.
- The existing native and screen-keyboard paths should remain usable. Phone pairing is an optional route through onboarding, never a prerequisite for setup.

## Options considered

| Option | Setup friction | Reach | Security and platform concerns | Recommendation |
| --- | --- | --- | --- | --- |
| QR → local TV web server | Low; no phone app or account | Same reachable LAN | TV must bind a server socket; client-isolated Wi-Fi and VLANs block it. Local HTTP needs an explicit credential threat model. Android 17 gates incoming local TCP for apps targeting API 37+. | Preferred product direction, subject to the credential transport gate |
| QR → public HTTPS companion + direct LAN API | Low after scan | Same reachable LAN, phone needs site access | Trusted HTTPS page can make secure-context local requests. Chrome's Local Network Access permission and CORS may add a prompt; HTTPS-to-local behavior and Safari/Chrome versions need device testing. | Strong web-based candidate for protected credentials |
| Cloud relay | Low and works across networks | Internet-connected devices | Requires service operations, abuse prevention, availability, privacy policy, and end-to-end encryption. Avoid relaying plaintext credentials or Immich media/auth tokens. | Later fallback if remote access across VLANs/networks is a requirement |
| Bluetooth / Web Bluetooth | Medium to high | Nearby radio range | Web Bluetooth is not available in all widely used browsers and requires secure context and user permission. Native-app Bluetooth adds platform permissions and pairing UX. | Do not use as the primary path |
| Native phone app | Medium; install required | Same LAN or relay | Can pin keys and use native network APIs, but adds a second product, release channel, maintenance, and support burden. | Revisit only if browser transport cannot meet security/reliability goals |
| Immich OAuth device authorization | Potentially very low | Depends on Immich support | Current client performs direct email/password or API-key auth; no device-authorization endpoint is present in this codebase. Do not invent an unofficial grant or upload Immich credentials to a new service. | Use only if Immich exposes a supported device flow in the future |

## Proposed user experience

### First-run setup

1. Keep the current **Screen keyboard** and **Device keyboard** choices. Add a third optional **Use phone** action on the URL or credential steps, with a visible **Continue on TV** fallback.
2. When the user selects phone setup, start a pairing session only while onboarding is visible. Show a QR code, a short manual URL/code fallback, an expiry timer, and clear same-network instructions.
3. The phone opens a responsive, touch-friendly page. It shows the Immich TV product name and a short pairing confirmation value that must match the TV. Do not ask the phone to install an app or create an Immich TV account.
4. The TV shows the action being enabled but does not require approval: scanning the QR connects the phone directly.
5. The phone collects the server URL and selected sign-in fields. It sends them to the TV-hosted endpoint; the TV applies values to the existing onboarding state and remains the source of truth for validation, sign-in, errors, and secure profile saving.
6. The phone never receives the authenticated Immich session or profile secrets back from the TV. Clear input fields from the companion as soon as the TV acknowledges delivery, and do not write credentials to browser storage, URL parameters, analytics, or logs.
7. Revoke the session on app background/termination or explicit disconnect.

This direct-connect model is a deliberate product trade-off, not a claim of secure cross-device authorization. It is intended for a trusted home network; the TV keeps the fallback keyboard path, and phones can be revoked from Settings.

### Future phone remote

The same paired browser session can grow into a remote page with:

- Text entry for the currently focused TV field, with clear/backspace/submit actions.
- A large directional pad and Select/Back controls.
- Playback controls for play/pause, seek, next/previous, and slideshow.
- Connection state, TV identity, and a prominent **Disconnect** / **Revoke phone** action.

Model remote actions as explicit, versioned commands (for example `navigate`, `activate`, `textInput`, `back`, `playback`) rather than sending arbitrary key codes or exposing general app internals. Validate each command against the current app state and allow only a small set of actions. Do not expose Immich API operations, arbitrary URL fetching, or media access through the remote endpoint.

Initial release should be foreground-only: the remote works while Immich TV is open and the pairing session is active. Do not add an Android foreground service just to keep a remote alive in the background. Show a useful disconnected state if Android suspends or kills the app. A persistent trusted-phone pairing can be considered later, with an on-TV device list and revocation controls.

## Proposed technical shape

### TV side

- Add a `RemotePairingService` abstraction in a platform/network boundary, independent of widgets and onboarding Cubits.
- Add a small local control server implementation for native targets. The web build cannot bind a Dart `HttpServer`; hide server startup behind a capability/implementation boundary and offer a graceful unavailable state on unsupported targets.
- Bind only while the feature is active. Bind a random high port; expose only the minimum endpoints required by pairing and remote control. Do not serve Immich APIs or directory/file paths.
- Prefer QR-encoded direct addressing so discovery is not needed for first connection. The QR payload should use an ephemeral TV address/port and pairing identifier. Include a manually enterable short code/address for camera or QR failures.
- Handle multiple network interfaces carefully: enumerate usable addresses, reject loopback/link-local candidates for the phone URL, and show a selectable/retry path if the TV has multiple LANs. IPv4 is the initial compatibility target; test IPv6 and bracketed IPv6 URLs before claiming support.
- Keep onboarding in its current state/Cubit flow. Phone messages should feed validated field values or high-level onboarding intents into this flow, not call auth repositories directly from the server.
- Add a separate `RemoteCommandController`/Cubit for the future remote. It should dispatch typed intents to app-facing state/controller APIs, not forge keyboard events globally.
- Stop the server and invalidate sessions deterministically on app lifecycle changes and all completion/error paths.

### Phone page and transport

- Keep the page very small, responsive, accessible, and self-contained. Avoid third-party scripts, analytics, fonts, or CDN dependencies on a page involved in credential entry.
- Use a versioned JSON schema and strict length/type limits. Validate input on the TV, even if the phone validates it first. Add sequence numbers or request IDs so duplicate/retried sends cannot double-submit sign-in.
- Use a request/response channel for onboarding first. A single WebSocket can be considered for the later interactive remote after the protocol and reconnect behavior are defined. Do not add a transport dependency before the local-network spike establishes what is needed.
- Same-origin local hosting reduces CORS complexity but is not a secure origin on a private HTTP address and does not authenticate the page. A public HTTPS page improves code integrity but connects cross-origin to a private TV endpoint; Chrome gates those requests behind Local Network Access permission for secure contexts, and the TV needs strict CORS/origin checks. Browser behavior must be verified before choosing.
- If a public HTTPS companion is selected, evaluate an ephemeral ECDH key exchange whose public-key fingerprint is carried in the on-TV QR. Encrypt credential payloads on the phone before sending them to the TV; the TV decrypts in memory and immediately routes fields into onboarding. Use an audited crypto library and reviewed protocol, not custom cryptography. This protects payloads from passive LAN observers; the HTTPS origin and TV confirmation are still essential to protect against code substitution and mis-pairing.
- No HTTP endpoint should accept requests from arbitrary internet origins, and no endpoint should be usable without an active pairing capability. Return no permissive wildcard CORS headers.

### Pairing and session controls

- Generate cryptographically random, single-use pairing secrets with at least 128 bits of entropy; keep only a hash/MAC of lookup secrets server-side where practical.
- Set a short pairing lifetime (for example, 2–5 minutes), one pending request, attempt throttling, and lockout/restart behavior. Treat those values as product/security review inputs, not hard-coded assumptions.
- Separate QR bootstrap credentials, the active remote-session credential, and Immich credentials. Never reuse an Immich API key or session token for remote pairing.
- Keep session state in memory only for the first release. Do not persist the phone's pairing token or form contents. Add revocation on TV and automatic revocation on timeout/app exit.
- Protect state-changing operations against CSRF/replay. Require an unguessable per-pair capability, validate the allowed Origin/Host, reject unexpected content types, and use a one-time handshake before accepting commands.
- Avoid query-string secrets because URLs can leak through browser history, referrers, proxy/server logs, and screenshots. If a bearer bootstrap value must be in the QR URL, put it in a fragment and exchange it immediately; never log it. Confirm the exact design during the threat-model review.
- Do not collect the phone's IP address or device identifiers beyond what is required for the active session. Do not retain access logs containing credentials or capabilities.

### Platform constraints to plan for

- Android currently has `INTERNET` permission. Android 17 (API 37+) requires `ACCESS_LOCAL_NETWORK` at runtime for local TCP traffic, including accepting an incoming connection. The project currently follows Flutter's SDK values for target SDK, so the permission work must be scheduled with the target-SDK upgrade and tested on an API 37 device.
- Router client isolation, guest Wi-Fi, separate VLANs, VPN routing, and some mesh configurations can prevent a phone from reaching the TV even when both show Wi-Fi connected. Detect connection failure and explain this plainly; do not silently fall back to a cloud relay.
- On iOS, native app local-network operations have privacy requirements. Safari-originated traffic is treated differently by Apple, but a future native iPhone app would need a local-network usage description, and Bonjour use would require declaring service types. The initial phone client is a browser page, not an iOS app.
- Chrome's Local Network Access work requires secure contexts for public-webpage-to-local-network requests and is permission-gated. A public HTTPS companion may have a prompt/CORS path; a TV-served page has a different origin/security profile. Test both on actual phones.
- Web Bluetooth is limited availability and requires a secure context and explicit permission. This makes it a poor cross-platform browser foundation for the requested “scan and use” workflow.
- A QR direct URL works only while the TV address is reachable and the service remains active. DHCP address changes only matter after a QR is already scanned; regenerate a session QR on retry.

## Delivery plan and exit criteria

### Phase 0 — Architecture spike (no credential transfer)

Build a disposable native prototype or branch that opens an ephemeral TCP/HTTP listener on Android TV and serves a static non-secret page. Scan the displayed QR from iOS Safari and Android Chrome; prove phone-to-TV POST and disconnect on app pause. Do not add QR pairing to production onboarding yet.

**Exit criteria:**

- Confirm the TV's reachable interface/address and listener behavior on at least two Android TV/Google TV devices.
- Confirm Chrome and Safari can open the direct QR URL and send a same-network request, recording prompts, warnings, and any browser-specific differences.
- Confirm behavior on Wi-Fi and Ethernet, IPv4 and IPv6 as feasible, and client isolation/guest networks.
- Record exact Android compile/target SDK used by the release build and verify Android 17 permission behavior.
- Make a written decision on credential confidentiality, page integrity, and whether an HTTPS companion/relay or local-only threat model is acceptable.

### Phase 1 — Phone-assisted onboarding

Implement the pairing service, QR screen, short-code/manual fallback, TV-side approval, mobile form, onboarding integration, transport security, expiry/retry/revocation, and feature-unavailable fallback.

**Exit criteria:**

- Both email/password and API-key setup work from the phone page and from the existing TV/device-keyboard paths.
- Server URL normalization/validation and Immich sign-in continue to use the existing repositories and error states.
- Passwords and API keys never appear in logs, analytics, URLs, QR payloads, preferences, or the phone's persistent storage.
- Pair expiry, cancel, replay, bad token, repeated failures, network drop, and app background all fail closed and recover without wedging onboarding.
- Android 17 permission denial and browser local-network denial provide actionable fallback instructions.

### Phase 2 — Remote MVP

Expose typed remote commands over the active paired session. Add text input plus directional, Select, Back, playback, and disconnect controls. Keep session foreground-only and avoid persistent trust.

**Exit criteria:**

- Every command is allowlisted, state-validated, size-limited, and rate-limited.
- TV action feedback is visible on both devices; reconnect/timeout does not execute stale duplicate commands.
- Pairing can be revoked from the TV immediately, and the phone page cannot operate after revocation.
- Remote works while app is in foreground and reports clearly when it does not.

### Phase 3 — Optional persistent phone and relay

Only after real-device feedback, consider remembered phones, a management/revoke screen, mDNS convenience discovery, or an end-to-end encrypted relay for separate networks. Persistent pairing must be opt-in, scoped, auditable, and revocable. A cloud relay is a separate product/privacy/operations decision.

## Production test matrix

| Area | Cases |
| --- | --- |
| TV hardware | Android TV and Google TV devices from at least two vendors; Wi-Fi and Ethernet; cold start; app pause/resume; process kill |
| Phone/browser | Current iOS Safari; Android Chrome; Samsung Internet if supported by target users; portrait/landscape; screen zoom/accessibility |
| Network | Same normal LAN; guest Wi-Fi; AP/client isolation; separate VLAN; VPN; no internet; DHCP address change; dual-stack IPv4/IPv6 |
| Pairing UX | QR scan; manual code; camera denied; expired QR; wrong code; multiple scans; cancel/deny; second phone; TV approval timeout |
| Input | URL with reverse-proxy subpath and `/api`; password with punctuation/non-ASCII; API key with punctuation; paste; backspace; clear; submit; validation errors |
| Security | Randomness/expiry; replay; brute force/rate limits; cross-origin requests; malicious Origin/Host; CSRF; oversized JSON; malformed UTF-8; log/referrer/history inspection; active-session revocation |
| Lifecycle | Pairing while onboarding; sign-in success/failure; app backgrounds during entry; TV sleeps; phone suspends; network changes; retry and reconnect |
| Accessibility | Large touch targets; screen reader labels; contrast/focus; one-handed layout; keyboard-only browser navigation; manual fallback when QR scanning is unavailable |

Widget/unit tests are useful for protocol and state behavior, but release acceptance requires real TV + phone testing. A desktop localhost test does not validate TV network interfaces, mobile browser permissions, AP isolation, Android 17 runtime permission, or app lifecycle behavior.

## Code areas likely to change

- `lib/src/features/onboarding/onboarding_flow.dart` — start/stop pairing and feed phone input into the existing flow.
- `lib/src/features/onboarding/widgets/onboarding_form.dart` — optional phone action and state presentation.
- New `lib/src/features/remote_pairing/` feature — pairing service, protocol/state, and eventually remote commands.
- `lib/app.dart` — inject service abstraction and platform implementation.
- `android/app/src/main/AndroidManifest.xml` and platform permission handling — only when Android target SDK/permissions require it.
- `docs/ANDROID_TV_PACKAGING.md`, `docs/RELEASE_CHECKLIST.md`, and `docs/DEVELOPMENT_CHECKLIST.md` — real-device pairing and remote acceptance steps.

Keep platform-specific listener/network implementation out of onboarding widgets, and keep the pairing protocol transport-independent so a later relay or native phone app can reuse its authorization model.

## Research references

- [OAuth 2.0 Device Authorization Grant (RFC 8628)](https://www.rfc-editor.org/rfc/rfc8628.html) — TV-class constrained-device interaction, QR/user codes, user approval, short lifetime, and polling pattern. This app should not claim to implement OAuth device flow unless Immich supports it.
- [Best Current Practice for Security of Cross-Device Flows (RFC 10027)](https://www.rfc-editor.org/rfc/rfc10027.html) — QR/code substitution and cross-device authorization threats and mitigations.
- [Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission) — Android 17/API 37 local-network runtime permission, including incoming TCP sockets.
- [Chrome Local Network Access guidance](https://developer.chrome.com/docs/modern-web-guidance/guides/security/local-network-access) — secure-context requirement and browser permission behavior for web-to-LAN connections.
- [Apple local network privacy (TN3179)](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) — native iOS app local-network permissions, Bonjour declarations, and Safari traffic distinction.
- [Web Bluetooth API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Bluetooth_API) — limited browser availability and secure-context/user-permission constraints.
