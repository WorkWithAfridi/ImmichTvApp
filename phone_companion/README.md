# Immich TV phone companion

This directory contains the page served by the TV during QR phone setup and phone remote control. It has no build step, third-party scripts, analytics, storage, or service worker.

## How it works

The TV app bundles the six files listed in `pubspec.yaml` and serves them from its own LAN address. The QR contains a link like `http://192.168.0.172:36043/#<invitation>`: scanning it loads the page straight from the TV, and the page talks to the same origin, so there is no external site, deployment, or CORS configuration.

Scanning **connects immediately**. There is no approval screen or verification code on the TV. Each phone receives its own session token and command sequence, so several phones can control the TV at the same time. A phone can disconnect from the remote page, and the TV can revoke phones from Settings.

`plain.js` is the transport used by `app.js`. It sends versioned onboarding input and remote commands over plain HTTP on the local network. `crypto.js` is retained for the legacy externally hosted HTTPS companion mode; the current `app.js` does not use it.

Security note: the plain local transport does not encrypt credentials or commands in transit. Use it only on a network you trust. The TV still validates the Immich server and performs sign-in and profile saving; the phone never receives an Immich session.

## Local checks

```text
npm test --prefix phone_companion
flutter test test/src/features/remote_pairing
```

Real Android TV + Android Chrome/iOS Safari validation remains a release gate.
